// govinfo-gao-capture / index.ts
//
// Supabase Edge Function that pulls GAO reports from the GovInfo API
// (GAOREPORTS collection) and stores them as thoughts with
// source_type='govinfo_gao'.
//
// Pull, not webhook: GovInfo has no push mechanism, so this runs on a
// schedule (pg_cron + pg_net). Each invocation drains a bounded batch and
// advances a watermark in `govinfo_sync_state`, so a backlog spreads across
// ticks instead of dying against the function wall-clock limit.
//
// Why GovInfo and not gao.gov: GPO publishes GAO's reports as an official
// collection with a documented API. Scraping gao.gov directly means fighting
// an Akamai edge that 403s datacenter traffic, for the same documents.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY")!;
const GOVINFO_API_KEY = Deno.env.get("GOVINFO_API_KEY")!;
const SYNC_SECRET = Deno.env.get("GOVINFO_SYNC_SECRET")!;

const GOVINFO_BASE = "https://api.govinfo.gov";
const OPENROUTER_BASE = "https://openrouter.ai/api/v1";
const SYNC_KEY = "gaoreports";

// One invocation's ceiling. GovInfo allows 1,000 per page, but each package
// costs a summary fetch plus an embedding call, so the binding constraint is
// our wall clock, not theirs.
const BATCH_SIZE = 25;

// text-embedding-3-small tops out at 8191 tokens. GAO reports run 60+ pages,
// so we embed the title plus the opening of the report text and keep the
// full-text link in metadata for retrieval. Embedding the whole document
// would truncate arbitrarily somewhere in the middle of the findings.
//
// The /packages/{id}/summary response carries NO abstract field (verified
// against the live API by smoke/verify-govinfo-shape.mjs), so the opening of
// the text is the closest thing to a usable summary. For GAO reports that is
// the Highlights page: why GAO did the study, what it found, what it
// recommends.
const MAX_EMBED_CHARS = 8000;

// Applied server-side by GovInfo so we don't pull (or pay to embed) all
// ~28k GAO reports. Tune this list to the practice areas you actually track.
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

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

interface SyncState {
  sync_key: string;
  collection_code: string;
  last_modified_mark: string;
  offset_mark: string | null;
  packages_ingested: number;
}

interface GovInfoResult {
  packageId: string;
  title?: string;
  dateIssued?: string;
  lastModified?: string;
  resultLink?: string;
}

function buildQuery(): string {
  const topics = TOPIC_TERMS.map((t) => (t.includes(" ") ? `"${t}"` : t)).join(" OR ");
  return `collection:(GAOREPORTS) AND (${topics})`;
}

// GovInfo's /search response nests results under a key that has moved
// between API revisions, and the docs describe it only as "structured
// similarly to the UI". Rather than hard-code one shape and fail silently
// against another, probe the known variants and log loudly if none match.
function extractResults(payload: Record<string, unknown>): GovInfoResult[] {
  for (const key of ["results", "packages", "resultSet"]) {
    const value = payload[key];
    if (Array.isArray(value)) return value as GovInfoResult[];
  }
  console.error(
    "GovInfo /search: no recognized results array. Top-level keys:",
    Object.keys(payload).join(", "),
  );
  return [];
}

async function searchPage(state: SyncState): Promise<{
  results: GovInfoResult[];
  nextOffsetMark: string | null;
}> {
  const res = await fetch(`${GOVINFO_BASE}/search?api_key=${GOVINFO_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query: `${buildQuery()} AND lastmodified:range(${state.last_modified_mark},)`,
      pageSize: BATCH_SIZE,
      offsetMark: state.offset_mark ?? "*",
      // Ascending so the watermark only ever moves forward. Sorting by score
      // or descending date would make a resumable cursor meaningless.
      sorts: [{ field: "lastModified", sortOrder: "ASC" }],
    }),
  });

  if (res.status === 429) {
    // api.data.gov sends Retry-After. Surface it instead of hammering:
    // the next cron tick is a better retry than a busy loop in-function.
    throw new Error(`GovInfo rate limit; retry after ${res.headers.get("Retry-After") ?? "?"}s`);
  }
  if (!res.ok) {
    throw new Error(`GovInfo search failed: ${res.status} ${await res.text()}`);
  }

  const payload = await res.json();
  return {
    results: extractResults(payload),
    nextOffsetMark: payload.nextPage ?? payload.offsetMark ?? null,
  };
}

async function fetchSummary(packageId: string): Promise<Record<string, any> | null> {
  const res = await fetch(
    `${GOVINFO_BASE}/packages/${packageId}/summary?api_key=${GOVINFO_API_KEY}`,
  );
  if (!res.ok) {
    console.error(`GovInfo summary failed (${packageId}): ${res.status}`);
    return null;
  }
  return await res.json();
}

// The summary endpoint has no abstract, so the opening of the report text is
// what we embed. Returns null rather than throwing: a report with an
// unreachable text link is still worth storing on its title and metadata.
async function fetchReportText(txtLink: string | null): Promise<string | null> {
  if (!txtLink) return null;

  const sep = txtLink.includes("?") ? "&" : "?";
  const res = await fetch(`${txtLink}${sep}api_key=${GOVINFO_API_KEY}`);
  if (!res.ok) {
    console.error(`GovInfo text fetch failed: ${res.status}`);
    return null;
  }

  // GovInfo serves these as HTML for most GAO packages. Strip tags and
  // collapse whitespace so the embedding sees prose, not markup.
  const raw = await res.text();
  const text = raw
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();

  return text.length > 0 ? text.slice(0, MAX_EMBED_CHARS) : null;
}

async function getEmbedding(text: string): Promise<number[]> {
  const r = await fetch(`${OPENROUTER_BASE}/embeddings`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "openai/text-embedding-3-small",
      input: text.slice(0, MAX_EMBED_CHARS),
    }),
  });
  const d = await r.json();
  return d.data[0].embedding;
}

// One query for the whole batch rather than one per package. Filters on
// source_type first so it uses idx_thoughts_source_type.
async function findAlreadyIngested(packageIds: string[]): Promise<Set<string>> {
  const { data, error } = await supabase
    .from("thoughts")
    .select("metadata->>govinfo_package_id")
    .eq("source_type", "govinfo_gao")
    .in("metadata->>govinfo_package_id", packageIds);

  if (error) {
    // Fail closed: if we can't confirm what's already stored, skip the batch
    // rather than risk duplicating every report in it.
    throw new Error(`Dedup check failed: ${error.message}`);
  }
  return new Set((data ?? []).map((r: any) => r.govinfo_package_id));
}

async function ingest(result: GovInfoResult): Promise<boolean> {
  const summary = await fetchSummary(result.packageId);
  if (!summary) return false;

  const title = summary.title ?? result.title ?? result.packageId;
  const txtLink = summary.download?.txtLink ?? null;
  const body = await fetchReportText(txtLink);
  const content = body ? `${title}\n\n${body}` : title;

  const embedding = await getEmbedding(content);

  const { error } = await supabase.from("thoughts").insert({
    content,
    embedding,
    source_type: "govinfo_gao",
    type: "reference",
    metadata: {
      source: "govinfo",
      govinfo_package_id: result.packageId,
      collection: "GAOREPORTS",
      title,
      // GAO's own report number (GAO-24-106356), which is how these get cited
      // in practice — the GovInfo packageId is not. The summary response has
      // no dedicated field for it, but packageId is reliably
      // "GAOREPORTS-<report number>", so derive it rather than guess a field.
      gao_report_number: result.packageId.replace(/^GAOREPORTS-/, ""),
      date_issued: summary.dateIssued ?? result.dateIssued ?? null,
      last_modified: result.lastModified ?? null,
      govinfo_url: result.resultLink ?? null,
      pdf_link: summary.download?.pdfLink ?? null,
      // Full text lives behind this link; `content` holds only its opening.
      text_link: txtLink,
      text_truncated: body != null && body.length >= MAX_EMBED_CHARS,
      branch: summary.branch ?? null,
    },
  });

  if (error) {
    console.error(`Insert failed (${result.packageId}):`, error);
    return false;
  }
  return true;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "GET") {
    return new Response("govinfo-gao-capture is live", { status: 200 });
  }

  // This function costs money to run (embeddings) and burns a shared API
  // quota, so it is not open to the internet. pg_cron passes this header.
  if (req.headers.get("x-sync-secret") !== SYNC_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  try {
    const { data: state, error: stateError } = await supabase
      .from("govinfo_sync_state")
      .select("sync_key, collection_code, last_modified_mark, offset_mark, packages_ingested")
      .eq("sync_key", SYNC_KEY)
      .single();

    if (stateError || !state) {
      throw new Error(`Sync state missing: run schemas/govinfo-sync-state/schema.sql`);
    }

    const { results, nextOffsetMark } = await searchPage(state as SyncState);

    if (results.length === 0) {
      await supabase
        .from("govinfo_sync_state")
        .update({ last_run_at: new Date().toISOString(), offset_mark: null, last_error: null })
        .eq("sync_key", SYNC_KEY);
      return Response.json({ status: "up-to-date", ingested: 0 });
    }

    const seen = await findAlreadyIngested(results.map((r) => r.packageId));
    const fresh = results.filter((r) => !seen.has(r.packageId));

    let ingested = 0;
    for (const result of fresh) {
      if (await ingest(result)) ingested++;
    }

    // Advance the watermark to the newest lastModified we actually saw. If
    // the page was fully consumed, clear offset_mark so the next run opens a
    // fresh window from the new watermark.
    const newestMark = results
      .map((r) => r.lastModified)
      .filter((m): m is string => Boolean(m))
      .sort()
      .pop();

    await supabase
      .from("govinfo_sync_state")
      .update({
        last_modified_mark: newestMark ?? (state as SyncState).last_modified_mark,
        offset_mark: results.length === BATCH_SIZE ? nextOffsetMark : null,
        last_run_at: new Date().toISOString(),
        last_error: null,
        packages_ingested: (state as SyncState).packages_ingested + ingested,
      })
      .eq("sync_key", SYNC_KEY);

    return Response.json({
      status: "ok",
      examined: results.length,
      skipped_duplicates: results.length - fresh.length,
      ingested,
      more: results.length === BATCH_SIZE,
    });
  } catch (err) {
    console.error("Function error:", err);
    await supabase
      .from("govinfo_sync_state")
      .update({ last_error: String(err), last_run_at: new Date().toISOString() })
      .eq("sync_key", SYNC_KEY);
    return new Response("error", { status: 500 });
  }
});
