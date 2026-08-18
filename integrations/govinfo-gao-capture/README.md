# GovInfo GAO Report Capture

Pulls GAO reports from the GovInfo API into your Open Brain on a schedule.

## What It Does

GAO publishes oversight reports that matter for elder law practice — Medicaid
program integrity, nursing home oversight, long-term care financing, VA
benefits administration. This integration watches the GovInfo `GAOREPORTS`
collection, filters to the topics you care about, and stores each new or
revised report as a thought with `source_type='govinfo_gao'`.

It runs on a schedule rather than a webhook, because GovInfo has no push
mechanism. Each run drains a bounded batch and advances a watermark, so a
large backlog spreads across ticks instead of timing out.

### Why GovInfo instead of scraping gao.gov

GPO publishes GAO's reports as an official collection with a documented API,
a stable package ID per report, and direct PDF and text links. Scraping
gao.gov gets you the same documents by fighting an Akamai edge that returns
403 to datacenter traffic — more fragile, slower, and against the grain of a
site that already gives the data away cleanly.

## Verify Before You Deploy

GPO documents the `/search` response shape only loosely, so run the shape
verifier against your own key first:

```bash
GOVINFO_API_KEY=your-key node integrations/govinfo-gao-capture/smoke/verify-govinfo-shape.mjs
```

Exit 0 means every field `index.ts` reads is present and the report text link
resolves to real prose. Exit 1 prints exactly what to change and where.

Pay attention to `titles_matching_a_topic_term` in the output. GovInfo searches
full text, so an unrelated-looking title is not automatically wrong — but if
none of the sampled titles relate to your topics, tighten `buildQuery()` before
deploying or you will embed a broad slice of GAO's catalog.

## Prerequisites

- A working Open Brain instance (`thoughts` table with pgvector)
- The `enhanced-thoughts` schema (provides `source_type` and its index)
- A free GovInfo API key: https://www.govinfo.gov/api-signup
- An OpenRouter key for embeddings
- Supabase CLI

## Cost

- **GovInfo API:** free. Default limits are 36,000 requests/hour, far above
  what a daily pull uses.
- **Embeddings:** one `text-embedding-3-small` call per new report, on the
  title plus the first 8,000 characters of the report. At typical GAO
  publication volume with a topic filter, this is cents per month.

The initial backfill is the only meaningful cost, and it is bounded by how
far back you set `last_modified_mark` in the schema file.

## Credential Tracker

| Secret | Where it comes from |
|---|---|
| `GOVINFO_API_KEY` | govinfo.gov/api-signup |
| `OPENROUTER_API_KEY` | openrouter.ai keys page |
| `GOVINFO_SYNC_SECRET` | You generate it; gates the function |

## Step 1: Apply the Schema

```bash
psql "$DATABASE_URL" -f schemas/govinfo-sync-state/schema.sql
```

This creates `govinfo_sync_state`, seeds the `gaoreports` cursor, and adds
the dedup index on `metadata->>'govinfo_package_id'`.

To backfill further than the default, edit `last_modified_mark` in that file
*before* running it, or update the row directly afterward.

## Step 2: Deploy the Function

```bash
supabase functions new govinfo-gao-capture
cp integrations/govinfo-gao-capture/index.ts \
   supabase/functions/govinfo-gao-capture/index.ts

supabase secrets set GOVINFO_API_KEY=your-key
supabase secrets set OPENROUTER_API_KEY=your-key
supabase secrets set GOVINFO_SYNC_SECRET="$(openssl rand -hex 32)"

supabase functions deploy govinfo-gao-capture
```

## Step 3: Schedule It

Daily is plenty — GAO publishes a handful of reports a day at most.

```sql
select cron.schedule(
  'govinfo-gao-capture',
  '0 6 * * *',
  $$
  select net.http_post(
    url     := 'https://YOUR-PROJECT.supabase.co/functions/v1/govinfo-gao-capture',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-sync-secret',  'YOUR_GOVINFO_SYNC_SECRET'
    )
  );
  $$
);
```

## Step 4: Test It

```bash
curl -X POST https://YOUR-PROJECT.supabase.co/functions/v1/govinfo-gao-capture \
  -H "x-sync-secret: YOUR_GOVINFO_SYNC_SECRET"
```

Expected response:

```json
{"status":"ok","examined":25,"skipped_duplicates":0,"ingested":25,"more":true}
```

`"more": true` means the batch filled and there is a backlog. Either wait for
the next cron tick or call it again to keep draining.

## What Gets Embedded

The `/packages/{id}/summary` response carries no abstract for GAO packages —
the shape verifier caught this against the live API. So the function fetches
`download.txtLink`, strips the HTML, and embeds the title plus the opening
8,000 characters. For GAO reports that opening is the Highlights page: why GAO
did the study, what it found, what it recommends.

Full text stays behind `metadata.text_link`, and `metadata.text_truncated`
flags reports whose body ran past the embedding window.

The citable report number (`GAO-05-943`) is derived from the GovInfo
`packageId`, which is reliably `GAOREPORTS-<report number>`. No summary field
carries it.

## Tuning the Topic Filter

`TOPIC_TERMS` at the top of `index.ts` is the server-side filter. It is not a
guess: it was derived by reviewing all 190 Implementation Factory items against
what GAO actually publishes. See `references/item-relevance.md` for the full
mapping and the reasoning behind each tier.

The query is scoped to **titles**, not full text. Searching full text matched a
highway congestion report on an elder-law query, because "medicare" appears
once in plenty of reports that are not about Medicare. GAO titles are strongly
topical, so title-scoping trades a little recall for a large gain in precision.

As verified against the live API, the shipped terms match **658 GAO reports** —
a targeted corpus, not a broad slice of GAO's ~28k catalog. Widen or narrow the
list to match your practice; every term you add increases how many reports get
embedded and stored.

## Troubleshooting

### `Sync state missing`

Step 1 didn't run, or ran against a different database. Confirm with
`select * from govinfo_sync_state;`.

### `no recognized results array` in the logs

GovInfo's `/search` response nests results under a key that has shifted
between API revisions. As of last verification it is `results`, with the
pagination cursor in `offsetMark`. If that changes, the function logs the
actual top-level keys it got — add the new key to `extractResults()`. Running
the shape verifier will tell you the same thing before it reaches production.

### Thoughts arrive with title only, no body

`download.txtLink` was unreachable for those packages, so `ingest()` fell back
to the title. Check the function logs for `GovInfo text fetch failed`. Run the
shape verifier to confirm the link resolves for a known-good package.

### Nothing ingested, `examined` is 0

The watermark has caught up. Check `last_modified_mark`; if it is in the
future or too recent, reset it:

```sql
update govinfo_sync_state
   set last_modified_mark = '2024-01-01T00:00:00Z', offset_mark = null
 where sync_key = 'gaoreports';
```

### Rate limit errors

The shared `DEMO_KEY` is heavily throttled. Make sure `GOVINFO_API_KEY` is
your own key from the signup page.

## What You Just Built

A standing research feed. GAO's oversight work on Medicaid, long-term care,
and veterans benefits lands in your brain as it publishes, semantically
searchable alongside everything else, with citations and full-text links
intact.
