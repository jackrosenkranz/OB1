#!/usr/bin/env node

// Pre-deploy check for integrations/govinfo-gao-capture.
//
// GPO documents the /search response only as "structured similarly to the UI
// search results", and the key holding the results array has moved between
// API revisions. index.ts probes a list of known variants; this script tells
// you which one your key actually returns, and whether every field the
// function reads is present, BEFORE you deploy and discover it at 6am from
// a cron log.
//
// Usage:
//   GOVINFO_API_KEY=your-key node smoke/verify-govinfo-shape.mjs
//
// Exit 0 = index.ts will work as written. Exit 1 = it needs the edit this
// script prints. Never prints the API key.

const apiKey = requiredEnv("GOVINFO_API_KEY");
const GOVINFO_BASE = "https://api.govinfo.gov";

// Kept in sync with index.ts. If you tune TOPIC_TERMS there, mirror it here
// so this script exercises the query you actually ship.
const TOPIC_TERMS = [
  "medicaid",
  "medicare",
  "long-term care",
  "nursing home",
  "elder abuse",
  "guardianship",
  "home and community-based services",
  "veterans benefits",
  "social security disability",
];

// The variants index.ts probes, in order.
const RESULT_KEY_CANDIDATES = ["results", "packages", "resultSet"];
const NEXT_PAGE_CANDIDATES = ["nextPage", "offsetMark"];

// Fields index.ts reads off each search result.
const SEARCH_FIELDS = {
  packageId: "required",
  title: "optional",
  dateIssued: "optional",
  lastModified: "required",
  resultLink: "optional",
};

// Fields index.ts reads off /packages/{id}/summary.
//
// Note what is NOT here: summary/abstract. The live API carries no abstract
// field for GAO packages, which this script caught on its first run. index.ts
// now fetches download.txtLink and embeds its opening instead, so txtLink is
// required rather than optional.
const SUMMARY_FIELDS = {
  title: "required",
  "download.txtLink": "required",
  "download.pdfLink": "optional",
  dateIssued: "optional",
  branch: "optional",
};

const findings = { search: {}, summary: {}, problems: [] };

async function main() {
  const search = await probeSearch();
  const pkg = await probeSummary(search.sampleId);

  const ok = findings.problems.length === 0;
  console.log(JSON.stringify({ ok, ...findings }, null, 2));

  if (!ok) {
    console.error("\n--- Action required ---");
    for (const p of findings.problems) console.error(`  • ${p}`);
    process.exit(1);
  }
  console.error("\nAll fields index.ts depends on are present. Safe to deploy.");
}

async function probeSearch() {
  const topics = TOPIC_TERMS.map((t) => (t.includes(" ") ? `"${t}"` : t)).join(" OR ");
  const payload = await request("/search", {
    method: "POST",
    body: {
      query: `collection:(GAOREPORTS) AND (${topics})`,
      pageSize: 5,
      offsetMark: "*",
      sorts: [{ field: "lastModified", sortOrder: "ASC" }],
    },
  });

  // Which key holds the array?
  const topLevelKeys = Object.keys(payload);
  const arrayKeys = topLevelKeys.filter((k) => Array.isArray(payload[k]));
  const matched = RESULT_KEY_CANDIDATES.find((k) => Array.isArray(payload[k]));

  findings.search.top_level_keys = topLevelKeys;
  findings.search.array_keys = arrayKeys;
  findings.search.results_key = matched ?? null;

  if (!matched) {
    findings.problems.push(
      arrayKeys.length
        ? `Results live under "${arrayKeys[0]}", which index.ts does not probe. ` +
          `Add "${arrayKeys[0]}" to RESULT_KEY_CANDIDATES in extractResults().`
        : `No array found in the /search response at all. Top-level keys: ${topLevelKeys.join(", ")}`,
    );
    return { sampleId: null };
  }

  const results = payload[matched];
  findings.search.result_count = results.length;

  if (results.length === 0) {
    findings.problems.push(
      "Query returned zero results. Widen TOPIC_TERMS or confirm GAOREPORTS has matching reports.",
    );
    return { sampleId: null };
  }

  // Pagination key
  const pageKey = NEXT_PAGE_CANDIDATES.find((k) => payload[k] != null);
  findings.search.next_page_key = pageKey ?? null;
  if (!pageKey) {
    findings.problems.push(
      "Neither nextPage nor offsetMark present; pagination will stall after one batch. " +
        "Check the response for the cursor field and update searchPage().",
    );
  }

  // Per-result fields, checked across the whole page rather than just [0] —
  // a field can be present on one report and absent on the next.
  const sample = results[0];
  findings.search.fields = {};
  for (const [field, requirement] of Object.entries(SEARCH_FIELDS)) {
    const presentCount = results.filter((r) => r?.[field] != null).length;
    findings.search.fields[field] = `${presentCount}/${results.length}`;
    if (requirement === "required" && presentCount < results.length) {
      findings.problems.push(
        `Search result field "${field}" is required by index.ts but missing on ` +
          `${results.length - presentCount} of ${results.length} results.`,
      );
    }
  }

  findings.search.sample_keys = Object.keys(sample);

  // Relevance check. GovInfo searches full text, so a topic term can match
  // deep inside a report whose title looks unrelated — one off-topic-looking
  // title is not a bug. But if NONE of the sampled titles relate to any topic
  // term, the query is probably not constraining the way index.ts assumes,
  // and the function would embed (and bill for) a broad slice of GAO output.
  const titles = results.map((r) => r.title ?? "");
  const onTopic = titles.filter((t) =>
    TOPIC_TERMS.some((term) => t.toLowerCase().includes(term.toLowerCase()))
  );
  findings.search.total_matching_count = payload.count ?? null;
  findings.search.titles_matching_a_topic_term = `${onTopic.length}/${titles.length}`;
  findings.search.sample_titles = titles.map((t) => t.slice(0, 90));

  if (onTopic.length === 0) {
    findings.problems.push(
      "None of the sampled titles contain any TOPIC_TERM. Review sample_titles " +
        "below: if they are unrelated to your practice areas, the query is not " +
        "filtering and you would ingest a broad slice of GAO output. Tighten " +
        "buildQuery() (try title:(...) instead of a bare term list) before deploying.",
    );
  }

  return { sampleId: sample.packageId ?? null };
}

async function probeSummary(packageId) {
  if (!packageId) {
    findings.summary.skipped = "no packageId from search step";
    return null;
  }

  const payload = await request(`/packages/${packageId}/summary`);
  findings.summary.package_id = packageId;
  findings.summary.top_level_keys = Object.keys(payload);
  findings.summary.fields = {};

  for (const [path, requirement] of Object.entries(SUMMARY_FIELDS)) {
    const value = readPath(payload, path);
    findings.summary.fields[path] = value == null ? "absent" : "present";

    if (requirement === "required" && value == null) {
      findings.problems.push(`Summary field "${path}" is required by index.ts but absent.`);
    }
  }

  // index.ts derives the citable report number from packageId rather than
  // from any summary field, because no summary field carries it.
  findings.summary.gao_report_number_derived = packageId.replace(/^GAOREPORTS-/, "");
  if (!findings.summary.gao_report_number_derived.startsWith("GAO-")) {
    findings.problems.push(
      `packageId "${packageId}" does not follow the GAOREPORTS-<report number> ` +
        "pattern that ingest() relies on; metadata.gao_report_number will be wrong.",
    );
  }

  await probeReportText(readPath(payload, "download.txtLink"));
  return payload;
}

// The text link is what index.ts actually embeds, so confirm it resolves to
// prose and not an error page or an empty shell.
async function probeReportText(txtLink) {
  if (!txtLink) {
    findings.summary.report_text = "skipped: no txtLink";
    return;
  }

  const sep = txtLink.includes("?") ? "&" : "?";
  const res = await fetch(`${txtLink}${sep}api_key=${apiKey}`);
  if (!res.ok) {
    findings.problems.push(`download.txtLink returned ${res.status}; ingest() would store title only.`);
    return;
  }

  const raw = await res.text();
  const text = raw
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  findings.summary.report_text = {
    raw_bytes: raw.length,
    stripped_chars: text.length,
    looks_like_html: /<\/?[a-z]/i.test(raw),
    opening: text.slice(0, 240),
  };

  // 500 chars is well under any real GAO report; below that we are almost
  // certainly looking at a stub or an error page.
  if (text.length < 500) {
    findings.problems.push(
      `download.txtLink yielded only ${text.length} chars of text; ` +
        "embeddings would be near-empty. Inspect the opening in this report.",
    );
  }
}

async function request(path, { method = "GET", body } = {}) {
  const url = `${GOVINFO_BASE}${path}${path.includes("?") ? "&" : "?"}api_key=${apiKey}`;
  const res = await fetch(url, {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });

  const remaining = res.headers.get("X-RateLimit-Remaining");
  if (remaining != null) findings.rate_limit_remaining = remaining;

  if (res.status === 429) {
    fail(
      `GovInfo rate limit hit (retry after ${res.headers.get("Retry-After") ?? "?"}s). ` +
        "If you are using DEMO_KEY, get your own at https://www.govinfo.gov/api-signup",
    );
  }
  if (res.status === 401) {
    fail("GovInfo returned 401: GOVINFO_API_KEY is missing or invalid.");
  }
  if (!res.ok) {
    // Redact the key in case GovInfo echoes the request URL back in the error.
    fail(`GovInfo ${method} ${path} failed: ${res.status} ${redact(await res.text())}`);
  }
  return await res.json();
}

function readPath(obj, path) {
  return path.split(".").reduce((acc, key) => (acc == null ? acc : acc[key]), obj);
}

function redact(text) {
  return String(text).replaceAll(apiKey, "[REDACTED]");
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) fail(`Set ${name}. Get a free key at https://www.govinfo.gov/api-signup`);
  return value;
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

main().catch((err) => fail(redact(err?.stack || err)));
