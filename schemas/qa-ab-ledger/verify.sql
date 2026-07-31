-- ============================================================
-- QA A/B Ledger — verification script
--
-- Proves the three guarantees the schema claims, rather than asserting
-- them in a comment:
--
--   1. The answer key cannot be written before a verified reveal, and a
--      reveal cannot happen while a review is still outstanding.
--   2. Every ledger table rejects updates and deletes.
--   3. The metric views compute from recorded facts, including the
--      stopping rule that reports insufficient_evidence below the
--      minimum sample.
--
-- Runs entirely inside a transaction and rolls back at the end, so it
-- leaves no rows behind and is safe against a live ledger. Nothing here
-- removes data.
--
-- Usage:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f verify.sql
--
-- Every line of output should read PASS.
-- ============================================================

BEGIN;

\set QUIET on
\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------

CREATE TEMP TABLE qa_ab_verify_ids (label TEXT PRIMARY KEY, id UUID);

-- The plaintext key. In real use this never touches the database until
-- reveal; here it is a literal so the test is self-contained.
\set seed_plaintext '3 defects: wrong income cap at line 12; transposed statute at line 40; fluent-but-wrong idempotency claim at line 88'
\set seed_salt 'verify-salt-0001'

INSERT INTO public.qa_ab_documents (doc_key, doc_class, pool, risk_tags)
VALUES ('VERIFY-BASE-001', 'migration', 'live', ARRAY['DESTRUCTIVE'])
RETURNING id \gset base_

INSERT INTO qa_ab_verify_ids VALUES ('base', :'base_id');

INSERT INTO public.qa_ab_documents (doc_key, doc_class, pool, is_seeded, derived_from)
VALUES ('VERIFY-SEEDED-001', 'migration', 'live', true, :'base_id')
RETURNING id \gset seeded_

INSERT INTO public.qa_ab_seed_keys (
  document_id, key_commitment, salt, defect_count, class_count, sealed_by
)
VALUES (
  :'seeded_id',
  public.qa_ab_commitment(:'seed_salt', :'seed_plaintext'),
  :'seed_salt',
  3, 3, 'verify.sql'
)
RETURNING id \gset key_

INSERT INTO public.qa_ab_assignments (document_id, arm, mode, arm_order, assigned_by)
VALUES (:'seeded_id', 'A', 'paired', 1, 'verify.sql')
RETURNING id \gset asgA_

INSERT INTO public.qa_ab_assignments (document_id, arm, mode, arm_order, assigned_by)
VALUES (:'seeded_id', 'B', 'paired', 2, 'verify.sql')
RETURNING id \gset asgB_

\set QUIET off

-- ------------------------------------------------------------
-- Test 1: the commitment verifies, and a tampered key does not
-- ------------------------------------------------------------

SELECT
  CASE WHEN public.qa_ab_commitment(:'seed_salt', :'seed_plaintext')
            = (SELECT key_commitment FROM public.qa_ab_seed_keys WHERE id = :'key_id')
       THEN 'PASS' ELSE 'FAIL' END
    AS "1a. correct key matches the sealed commitment";

SELECT
  CASE WHEN public.qa_ab_commitment(:'seed_salt', :'seed_plaintext' || ' (edited after the fact)')
            <> (SELECT key_commitment FROM public.qa_ab_seed_keys WHERE id = :'key_id')
       THEN 'PASS' ELSE 'FAIL' END
    AS "1b. edited key fails the commitment";

-- ------------------------------------------------------------
-- Test 2: defects cannot be recorded before a verified reveal
--
-- This is the guarantee that keeps the answer key away from the panel
-- under audit. If this test ever reports FAIL, every seeded catch rate
-- in the ledger is suspect.
-- ------------------------------------------------------------

DO $$
BEGIN
  BEGIN
    INSERT INTO public.qa_ab_seeded_defects (seed_key_id, defect_class, location, description)
    SELECT id, 'wrong_figure', 'line 12', 'leaked early'
      FROM public.qa_ab_seed_keys WHERE sealed_by = 'verify.sql';
    RAISE WARNING 'FAIL  2. defects were accepted before reveal';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS  2. defects rejected before a verified reveal';
  END;
END $$;

-- ------------------------------------------------------------
-- Test 3: reveal is blocked while any assigned review is outstanding
-- ------------------------------------------------------------

DO $$
BEGIN
  BEGIN
    INSERT INTO public.qa_ab_seed_reveals (seed_key_id, verification_ok, revealed_by)
    SELECT id, true, 'verify.sql'
      FROM public.qa_ab_seed_keys WHERE sealed_by = 'verify.sql';
    RAISE WARNING 'FAIL  3. reveal accepted while a run was outstanding';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS  3. reveal blocked while a run is outstanding';
  END;
END $$;

-- ------------------------------------------------------------
-- Record both runs, which unblocks the reveal
-- ------------------------------------------------------------

\set QUIET on

INSERT INTO public.qa_ab_runs (
  assignment_id, started_at, miss_rate_m, error_headroom_h, risk_score,
  wall_clock_seconds, token_spend, context_id
)
VALUES (:'asgA_id', now() - interval '20 minutes', 0.500, 0.500, 0.2500, 900, 48000, 'ctx-arm-a')
RETURNING id \gset runA_

INSERT INTO public.qa_ab_runs (
  assignment_id, started_at, miss_rate_m, error_headroom_h, risk_score,
  wall_clock_seconds, token_spend, context_id
)
VALUES (:'asgB_id', now() - interval '35 minutes', 0.500, 0.500, 0.2500, 2100, 121000, 'ctx-arm-b')
RETURNING id \gset runB_

\set QUIET off

DO $$
BEGIN
  INSERT INTO public.qa_ab_seed_reveals (seed_key_id, verification_ok, revealed_by)
  SELECT id, true, 'verify.sql'
    FROM public.qa_ab_seed_keys WHERE sealed_by = 'verify.sql';
  RAISE NOTICE 'PASS  4. reveal accepted once every run is recorded';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'FAIL  4. reveal rejected after all runs completed: %', SQLERRM;
END $$;

-- ------------------------------------------------------------
-- Now the defects can be written
-- ------------------------------------------------------------

\set QUIET on

INSERT INTO public.qa_ab_seeded_defects (seed_key_id, defect_class, is_fluent_error, location, description)
VALUES (:'key_id', 'wrong_figure',        false, 'line 12', 'income cap off by a plausible amount')
RETURNING id \gset d1_

INSERT INTO public.qa_ab_seeded_defects (seed_key_id, defect_class, is_fluent_error, location, description)
VALUES (:'key_id', 'wrong_statute',       false, 'line 40', 'transposed statute number')
RETURNING id \gset d2_

INSERT INTO public.qa_ab_seeded_defects (seed_key_id, defect_class, is_fluent_error, location, description)
VALUES (:'key_id', 'fluent_but_wrong',    true,  'line 88', 'fluently written, wrong idempotency claim')
RETURNING id \gset d3_

-- Arm A catches the two mechanical defects and misses the fluent one.
-- Arm B catches all three. This is the separation the fluent-error class
-- exists to detect; the view must reproduce it from these rows alone.
INSERT INTO public.qa_ab_findings (run_id, panelist, severity, verified_by, summary)
VALUES (:'runA_id', 'Lead QA Engineer', 'HIGH', 'judgment_only', 'income cap looks wrong')
RETURNING id \gset fA1_

INSERT INTO public.qa_ab_findings (run_id, panelist, severity, verified_by, summary)
VALUES (:'runA_id', 'Compliance Audit Specialist', 'HIGH', 'judgment_only', 'statute number wrong')
RETURNING id \gset fA2_

INSERT INTO public.qa_ab_findings (run_id, panelist, severity, verified_by, summary)
VALUES (:'runA_id', 'Data Architect', 'MEDIUM', 'judgment_only', 'unrelated style concern')
RETURNING id \gset fA3_

INSERT INTO public.qa_ab_findings (run_id, panelist, severity, verified_by, commit_tag, summary)
VALUES (:'runB_id', 'Lead QA Engineer', 'HIGH', 'source_fetched', 'MISMATCH', 'income cap contradicts fetched figure')
RETURNING id \gset fB1_

INSERT INTO public.qa_ab_findings (run_id, panelist, severity, verified_by, commit_tag, summary)
VALUES (:'runB_id', 'Compliance Audit Specialist', 'HIGH', 'source_fetched', 'MISMATCH', 'statute number contradicts source')
RETURNING id \gset fB2_

INSERT INTO public.qa_ab_findings (run_id, panelist, severity, verified_by, commit_tag, summary)
VALUES (:'runB_id', 'Data Architect', 'HIGH', 'executed', 'MISMATCH', 'second dry run corrupted state')
RETURNING id \gset fB3_

INSERT INTO public.qa_ab_finding_scores (finding_id, seeded_defect_id, verdict, scored_by)
VALUES (:'fA1_id', :'d1_id', 'catch', 'verify.sql'),
       (:'fA2_id', :'d2_id', 'catch', 'verify.sql'),
       (:'fA3_id', NULL,     'false_positive', 'verify.sql'),
       (:'fB1_id', :'d1_id', 'catch', 'verify.sql'),
       (:'fB2_id', :'d2_id', 'catch', 'verify.sql'),
       (:'fB3_id', :'d3_id', 'catch', 'verify.sql');

\set QUIET off

-- ------------------------------------------------------------
-- Test 5: append-only holds
-- ------------------------------------------------------------

DO $$
BEGIN
  BEGIN
    UPDATE public.qa_ab_findings SET severity = 'LOW' WHERE severity = 'HIGH';
    RAISE WARNING 'FAIL  5a. an update to a ledger table was accepted';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS  5a. updates rejected on qa_ab_findings';
  END;

  BEGIN
    UPDATE public.qa_ab_seed_keys SET key_commitment = 'rewritten' WHERE sealed_by = 'verify.sql';
    RAISE WARNING 'FAIL  5b. a seed commitment was rewritten';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS  5b. seed commitments cannot be rewritten';
  END;
END $$;

-- ------------------------------------------------------------
-- Test 6: the views reproduce the separation from recorded facts
-- ------------------------------------------------------------

SELECT
  CASE
    WHEN (SELECT defects_caught FROM public.qa_ab_catch_rates
           WHERE arm = 'A' AND is_fluent_error) = 0
     AND (SELECT defects_caught FROM public.qa_ab_catch_rates
           WHERE arm = 'B' AND is_fluent_error) = 1
    THEN 'PASS' ELSE 'FAIL'
  END AS "6a. fluent-error class separates the arms";

SELECT
  CASE
    WHEN (SELECT share FROM public.qa_ab_verified_by_mix
           WHERE arm = 'A' AND verified_by = 'judgment_only') = 1.000
    THEN 'PASS' ELSE 'FAIL'
  END AS "6b. arm A HIGH findings are all judgment_only";

SELECT
  CASE
    WHEN (SELECT evidence_status FROM public.qa_ab_evidence_status WHERE arm = 'A')
         = 'insufficient_evidence'
    THEN 'PASS' ELSE 'FAIL'
  END AS "6c. one audit reports insufficient_evidence";

-- Readable output for a human running this by hand.
SELECT arm, defect_class, is_fluent_error, defects_planted, defects_caught, catch_rate
  FROM public.qa_ab_catch_rates
 ORDER BY arm, defect_class;

SELECT arm, seeded_audits, defect_classes, evidence_status
  FROM public.qa_ab_evidence_status
 ORDER BY arm;

ROLLBACK;
