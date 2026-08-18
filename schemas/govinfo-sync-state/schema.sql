-- GovInfo Sync State
-- Watermark table for scheduled GovInfo API pulls (GAOREPORTS and any
-- other collection). Safe to run multiple times (fully idempotent).
--
-- Scheduled pulls are resumable: each Edge Function invocation processes a
-- bounded batch, then advances the watermark. The next cron tick picks up
-- where the last one stopped, so a large backlog drains across several runs
-- instead of dying against the function wall-clock limit.

CREATE TABLE IF NOT EXISTS public.govinfo_sync_state (
  sync_key           TEXT PRIMARY KEY,
  collection_code    TEXT NOT NULL,
  -- GovInfo filters on lastModified (when a package was added/updated in
  -- GovInfo), NOT publication date. Reports get revised, so a report issued
  -- years ago can surface with a recent lastModified. That is intended:
  -- a revised report is worth re-reading.
  last_modified_mark TIMESTAMPTZ NOT NULL DEFAULT '2020-01-01T00:00:00Z',
  -- Opaque GovInfo pagination cursor. Non-null means the previous run
  -- stopped mid-page and the next run should resume from here rather than
  -- restarting the window.
  offset_mark        TEXT,
  last_run_at        TIMESTAMPTZ,
  last_error         TEXT,
  packages_ingested  INTEGER NOT NULL DEFAULT 0,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed the GAO reports cursor. ON CONFLICT DO NOTHING so re-running this
-- file never rewinds a live watermark and re-ingests everything.
INSERT INTO public.govinfo_sync_state (sync_key, collection_code, last_modified_mark)
VALUES ('gaoreports', 'GAOREPORTS', '2024-01-01T00:00:00Z')
ON CONFLICT (sync_key) DO NOTHING;

-- Dedup support: the function looks up already-ingested packages by
-- metadata->>'govinfo_package_id' before embedding anything.
--
-- Indexed on ai_brain.thoughts, the base table. On instances where
-- public.thoughts is a view over it, indexing the view is not possible; on
-- instances where thoughts lives directly in public, change the schema
-- qualifier here to match.
CREATE INDEX IF NOT EXISTS idx_thoughts_govinfo_package_id
  ON ai_brain.thoughts ((metadata->>'govinfo_package_id'))
  WHERE metadata ? 'govinfo_package_id';
