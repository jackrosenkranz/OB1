# GovInfo Sync State

Watermark table for scheduled GovInfo API pulls.

## What It Adds

| Object | Purpose |
|---|---|
| `govinfo_sync_state` | One row per collection being synced; tracks position and run health |
| `idx_thoughts_govinfo_package_id` | Partial index supporting dedup by GovInfo package ID |

## Why a Watermark

Supabase Edge Functions have a wall-clock limit, and GovInfo collections are
large. A run that tries to ingest everything dies partway and leaves no record
of how far it got. This table makes pulls resumable: each run processes a
bounded batch, advances `last_modified_mark`, and stores `offset_mark` if it
stopped mid-page. The next run picks up from there.

`last_modified_mark` tracks GovInfo's `lastModified` — when a package was added
or updated in GovInfo, not its publication date. A report issued years ago can
resurface with a recent `lastModified` when GAO revises it. That is intended:
a revised report is worth re-reading.

## Apply

```bash
psql "$DATABASE_URL" -f schemas/govinfo-sync-state/schema.sql
```

Idempotent. The seed row uses `ON CONFLICT DO NOTHING`, so re-running never
rewinds a live watermark and re-ingests everything.

## Adjusting the Backfill Window

The `gaoreports` row seeds at `2024-01-01`. To pull more history, edit that
value before first run, or afterward:

```sql
update govinfo_sync_state
   set last_modified_mark = '2020-01-01T00:00:00Z', offset_mark = null
 where sync_key = 'gaoreports';
```

## Used By

- `integrations/govinfo-gao-capture`
