-- ============================================================
-- QA A/B Ledger — append-only evidence store for two-arm review panels
--
-- Purpose: a QA review panel is itself a measuring instrument, and an
-- unmeasured instrument drifts. This schema records the facts a panel
-- A/B test produces (assignments, findings, seeded-defect audits, gate
-- decisions, execution outcomes) and derives every metric from them,
-- so catch rate and acceptance rate can never be stale or hand-adjusted.
--
-- The design answers three requirements that plain files cannot meet:
--
--   1. The answer key must be unreachable during review. A seeded-error
--      audit is only valid if the panel never sees which defects were
--      planted. A markdown file in a repo is readable by the same agent
--      being audited. Here the key is sealed as a hash commitment, and
--      the defect rows do not exist in the database at all until a
--      verified reveal (see qa_ab_seed_reveals + the reveal gate).
--
--   2. History must not be rewritten. Every table is append-only,
--      enforced by trigger, not by convention. Facts that arrive later
--      (a gate decision, a score, an execution outcome) are separate
--      rows in separate tables rather than updates to earlier ones.
--
--   3. Metrics must be derived, never stored. Catch rate is defects
--      caught over defects planted. Storing that number alongside the
--      raw audits creates two sources of truth that can disagree.
--      All metrics here are views.
--
-- All changes are additive. public.thoughts is not altered in any way.
-- Optional links to thoughts(id) are nullable and use ON DELETE SET NULL,
-- so ledger rows outlive the notes that describe them.
--
-- Safe to run more than once (fully idempotent).
-- ============================================================

BEGIN;

-- Fail early and legibly if the base Open Brain schema is absent.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'thoughts'
  ) THEN
    RAISE EXCEPTION
      'qa-ab-ledger requires public.thoughts. Run docs/01-getting-started.md first.';
  END IF;
END $$;

-- digest() for the seed key commitment.
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================================
-- Shared machinery
-- ============================================================

-- Append-only guard. Attached to every ledger table below.
--
-- The protocol this schema serves states "Never edit history." That is a
-- norm in a markdown file and an invariant here. Corrections are new
-- rows, not edits.
CREATE OR REPLACE FUNCTION public.qa_ab_append_only()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'qa-ab-ledger: %.% is append-only. Record a correcting row instead of rewriting history.',
    TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END;
$$;

-- Commitment helper. Returns the hex digest that seals a seed key.
--
-- Usage at seeding time (run this OUTSIDE any context that will later
-- perform a review, and keep the plaintext key offline until reveal):
--   SELECT public.qa_ab_commitment('<random salt>', '<full plaintext key>');
--
-- The salt is stored in the clear alongside the commitment. A salt alone
-- reveals nothing; it exists so two audits that happen to plant the same
-- defect list do not produce the same commitment.
CREATE OR REPLACE FUNCTION public.qa_ab_commitment(
  salt TEXT,
  plaintext TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT encode(digest(salt || '::' || plaintext, 'sha256'), 'hex');
$$;


-- ============================================================
-- 1. Documents under review
-- ============================================================

CREATE TABLE IF NOT EXISTS public.qa_ab_documents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Stable human-facing identifier, e.g. an Implementation Factory item
  -- code or a migration name. Unique so assignments cannot silently
  -- attach to the wrong artifact.
  doc_key       TEXT NOT NULL UNIQUE,

  -- What kind of work this is. Catch rates are only comparable within a
  -- class, so this drives most of the reporting.
  doc_class     TEXT NOT NULL,

  -- Which evaluation pool the document belongs to.
  --   live         real work flowing through the panel
  --   known_good   executed cleanly; both arms SHOULD approve these.
  --                An arm that rejects known-good work is over-harsh,
  --                which makes its signal weak, not strong.
  --   adversarial  approved by some arm and later failed in execution
  pool          TEXT NOT NULL DEFAULT 'live'
    CHECK (pool IN ('live', 'known_good', 'adversarial')),

  -- Operation risk tags, e.g. {DESTRUCTIVE, IRREVERSIBLE}.
  risk_tags     TEXT[] NOT NULL DEFAULT '{}',

  -- True when this row is a mutated copy carrying planted defects.
  -- Reviewers are never told this; the audit is blind by design.
  is_seeded     BOOLEAN NOT NULL DEFAULT false,

  -- For a seeded copy, the untouched original it was derived from.
  derived_from  UUID REFERENCES public.qa_ab_documents(id),

  -- Optional pointer at an Open Brain note describing the artifact.
  thought_id    UUID REFERENCES public.thoughts(id) ON DELETE SET NULL,

  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- A seeded copy must say what it was derived from, otherwise the audit
  -- cannot be compared against the unmutated baseline.
  CONSTRAINT qa_ab_documents_seeded_needs_origin
    CHECK (NOT is_seeded OR derived_from IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS qa_ab_documents_class_idx
  ON public.qa_ab_documents (doc_class);
CREATE INDEX IF NOT EXISTS qa_ab_documents_pool_idx
  ON public.qa_ab_documents (pool);


-- ============================================================
-- 2. Arm assignments
-- ============================================================

CREATE TABLE IF NOT EXISTS public.qa_ab_assignments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id    UUID NOT NULL REFERENCES public.qa_ab_documents(id),

  arm            TEXT NOT NULL CHECK (arm IN ('A', 'B')),

  --   paired        both arms review the same document in separate
  --                 contexts; strongest comparison, double cost
  --   alternating   assignment by ledger sequence; default for live work
  mode           TEXT NOT NULL CHECK (mode IN ('paired', 'alternating')),

  -- True when a human named the arm instead of taking the ledger's
  -- assignment. Self-selected assignment biases the comparison, so it is
  -- recorded rather than forbidden.
  is_override    BOOLEAN NOT NULL DEFAULT false,

  -- In paired mode, the randomized order this arm ran in (1 or 2).
  arm_order      SMALLINT CHECK (arm_order IN (1, 2)),

  -- Which review round this is for the document. Round 3+ passes are
  -- treated as suspect: repeated resubmission inflates a panel's pass
  -- rate without improving the work.
  revision_round SMALLINT NOT NULL DEFAULT 1 CHECK (revision_round >= 1),

  assigned_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  assigned_by    TEXT,

  UNIQUE (document_id, arm, revision_round)
);

CREATE INDEX IF NOT EXISTS qa_ab_assignments_document_idx
  ON public.qa_ab_assignments (document_id);


-- ============================================================
-- 3. Runs (inserted at completion, never updated)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.qa_ab_runs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id       UUID NOT NULL REFERENCES public.qa_ab_assignments(id),

  started_at          TIMESTAMPTZ NOT NULL,
  completed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Triage inputs recorded as used, not as recomputed later.
  --   miss_rate_m       the panel's historical miss rate for this class
  --   error_headroom_h  how likely this class is to contain errors
  --   risk_score        M x H, stored so the threshold decision is auditable
  miss_rate_m         NUMERIC(4,3) CHECK (miss_rate_m BETWEEN 0 AND 1),
  error_headroom_h    NUMERIC(4,3) CHECK (error_headroom_h BETWEEN 0 AND 1),
  risk_score          NUMERIC(5,4) CHECK (risk_score BETWEEN 0 AND 1),

  -- Cost, so a catch-rate win that costs three times as much is visible
  -- as such rather than reported as a clean victory.
  wall_clock_seconds  INTEGER CHECK (wall_clock_seconds >= 0),
  token_spend         INTEGER CHECK (token_spend >= 0),
  tool_calls          INTEGER CHECK (tool_calls >= 0),

  -- Opaque identifier for the context the run happened in. Two arms
  -- sharing a context_id on the same document is contamination: one
  -- arm's findings leaked into the other. The calibration view surfaces
  -- this rather than silently averaging it in.
  context_id          TEXT,

  -- Optional pointer at the stored report.
  report_thought_id   UUID REFERENCES public.thoughts(id) ON DELETE SET NULL,

  CONSTRAINT qa_ab_runs_completed_after_start
    CHECK (completed_at >= started_at)
);

CREATE INDEX IF NOT EXISTS qa_ab_runs_assignment_idx
  ON public.qa_ab_runs (assignment_id);


-- ============================================================
-- 4. Findings
-- ============================================================

CREATE TABLE IF NOT EXISTS public.qa_ab_findings (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id       UUID NOT NULL REFERENCES public.qa_ab_runs(id),

  panelist     TEXT NOT NULL,
  severity     TEXT NOT NULL CHECK (severity IN ('HIGH', 'MEDIUM', 'LOW')),

  -- How the finding was established. This is the column that separates a
  -- verified defect from a confident opinion.
  --   executed        a script, dry run, or test produced the result
  --   source_fetched  a figure or citation was retrieved from a source
  --   judgment_only   the panel reasoned its way there and nothing
  --                   outside the panel confirmed it
  verified_by  TEXT NOT NULL
    CHECK (verified_by IN ('executed', 'source_fetched', 'judgment_only')),

  -- Commit-first arms only. NULL for arms that see the candidate first.
  --   MATCH        candidate satisfies the reviewer's prior commitment
  --   MISMATCH     candidate contradicts it
  --   NOT_COVERED  the commitment was silent; judgment only
  commit_tag   TEXT CHECK (commit_tag IN ('MATCH', 'MISMATCH', 'NOT_COVERED')),

  summary      TEXT NOT NULL,
  location     TEXT,
  detail       TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS qa_ab_findings_run_idx
  ON public.qa_ab_findings (run_id);
CREATE INDEX IF NOT EXISTS qa_ab_findings_verified_by_idx
  ON public.qa_ab_findings (verified_by);


-- ============================================================
-- 5. Gate decisions (a separate event, not a column on the run)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.qa_ab_gate_decisions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id      UUID NOT NULL REFERENCES public.qa_ab_runs(id),

  decision    TEXT NOT NULL
    CHECK (decision IN ('APPROVED', 'CONDITIONAL', 'HOLD')),

  decided_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Gate decisions are issued by a person, not by the panel. Recording
  -- who issued it keeps that true in the data.
  decided_by  TEXT NOT NULL,
  rationale   TEXT,

  UNIQUE (run_id)
);


-- ============================================================
-- 6. Seed keys — sealed before review, revealed after
-- ============================================================

-- The commitment is written when the defects are planted. The plaintext
-- key stays outside the database until every assigned run has completed.
-- Nothing here tells a reviewer what was planted.
CREATE TABLE IF NOT EXISTS public.qa_ab_seed_keys (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id      UUID NOT NULL UNIQUE REFERENCES public.qa_ab_documents(id),

  -- sha256 of salt || '::' || plaintext key. See qa_ab_commitment().
  key_commitment   TEXT NOT NULL,
  commitment_algo  TEXT NOT NULL DEFAULT 'sha256',
  salt             TEXT NOT NULL,

  -- Declared shape of the audit, safe to expose: knowing that four
  -- defects across three classes exist does not say which or where.
  -- Bounds match the protocol (k = 3 to 6, at least 3 classes).
  defect_count     SMALLINT NOT NULL CHECK (defect_count BETWEEN 3 AND 6),
  class_count      SMALLINT NOT NULL CHECK (class_count >= 3),

  sealed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  sealed_by        TEXT NOT NULL,

  CONSTRAINT qa_ab_seed_keys_class_fits_defects
    CHECK (class_count <= defect_count)
);


-- The reveal event. verification_ok records whether the plaintext key
-- presented at reveal actually hashed to the sealed commitment.
--
-- A false here voids the audit: either the key was edited after the
-- reviews ran, or the wrong key was presented. Both are recorded rather
-- than corrected, because a voided audit is itself a finding about the
-- process.
CREATE TABLE IF NOT EXISTS public.qa_ab_seed_reveals (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seed_key_id      UUID NOT NULL UNIQUE REFERENCES public.qa_ab_seed_keys(id),

  verification_ok  BOOLEAN NOT NULL,
  revealed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  revealed_by      TEXT NOT NULL,
  notes            TEXT
);


-- The planted defects. These rows do not exist until a verified reveal,
-- enforced by the trigger below. This is the mechanism that keeps the
-- answer key out of reach of the panel being audited.
CREATE TABLE IF NOT EXISTS public.qa_ab_seeded_defects (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seed_key_id     UUID NOT NULL REFERENCES public.qa_ab_seed_keys(id),

  -- Defect taxonomy. Extend freely; the views group by whatever is here.
  -- Suggested classes: wrong_figure, wrong_statute, off_by_one_date,
  -- non_idempotent_step, unexecutable_rollback, broken_lineage,
  -- fluent_but_wrong.
  defect_class    TEXT NOT NULL,

  -- The plausible-but-wrong class, reported separately. This is the class
  -- a panel that scores plausibility is predicted to miss, so if the arms
  -- do not separate here, the anchoring mechanism is not doing its job.
  is_fluent_error BOOLEAN NOT NULL DEFAULT false,

  location        TEXT NOT NULL,
  description     TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS qa_ab_seeded_defects_key_idx
  ON public.qa_ab_seeded_defects (seed_key_id);


-- ============================================================
-- 7. Scoring — findings judged against the revealed key
-- ============================================================

CREATE TABLE IF NOT EXISTS public.qa_ab_finding_scores (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  finding_id        UUID NOT NULL UNIQUE REFERENCES public.qa_ab_findings(id),

  -- Set only for verdict = 'catch'.
  seeded_defect_id  UUID REFERENCES public.qa_ab_seeded_defects(id),

  --   catch                  the finding maps to a planted defect
  --   false_positive         the finding corresponds to no real defect
  --   real_defect_unseeded   a genuine defect that was not planted.
  --                          Verify before counting: a finding that turns
  --                          out to be real is a catch, not a false
  --                          positive, and must not be scored as one.
  verdict           TEXT NOT NULL
    CHECK (verdict IN ('catch', 'false_positive', 'real_defect_unseeded')),

  scored_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  scored_by         TEXT NOT NULL,
  rationale         TEXT,

  CONSTRAINT qa_ab_finding_scores_catch_needs_defect
    CHECK (
      (verdict = 'catch' AND seeded_defect_id IS NOT NULL)
      OR (verdict <> 'catch' AND seeded_defect_id IS NULL)
    )
);


-- ============================================================
-- 8. Execution outcomes — the slow metric that matters most
-- ============================================================

CREATE TABLE IF NOT EXISTS public.qa_ab_execution_outcomes (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id             UUID NOT NULL REFERENCES public.qa_ab_runs(id),

  --   clean                  executed without incident
  --   required_correction    executed but needed post-approval fixes
  --   failed_in_execution    did not work; feeds the adversarial pool
  outcome            TEXT NOT NULL
    CHECK (outcome IN ('clean', 'required_correction', 'failed_in_execution')),

  observed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  description        TEXT,
  corrective_action  TEXT
);

CREATE INDEX IF NOT EXISTS qa_ab_execution_outcomes_run_idx
  ON public.qa_ab_execution_outcomes (run_id);


-- ============================================================
-- Reveal gates
-- ============================================================

-- A reveal may not happen while any assigned run is still outstanding.
-- Revealing early would put the answer key in the database while a panel
-- is still working, which is the exact failure this schema exists to
-- prevent.
CREATE OR REPLACE FUNCTION public.qa_ab_guard_reveal()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  outstanding INTEGER;
BEGIN
  SELECT COUNT(*)
    INTO outstanding
    FROM public.qa_ab_assignments a
    LEFT JOIN public.qa_ab_runs r ON r.assignment_id = a.id
   WHERE a.document_id = (
           SELECT k.document_id
             FROM public.qa_ab_seed_keys k
            WHERE k.id = NEW.seed_key_id
         )
     AND r.id IS NULL;

  IF outstanding > 0 THEN
    RAISE EXCEPTION
      'qa-ab-ledger: % assigned review(s) have not completed for this seed key.',
      outstanding
      USING HINT = 'Record every run first. Revealing now would expose the answer key mid-audit.',
            ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- Seeded defect rows may only be written after a verified reveal.
CREATE OR REPLACE FUNCTION public.qa_ab_require_reveal()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM public.qa_ab_seed_reveals rv
     WHERE rv.seed_key_id = NEW.seed_key_id
       AND rv.verification_ok
  ) THEN
    RAISE EXCEPTION
      'qa-ab-ledger: no verified reveal exists for seed key %.', NEW.seed_key_id
      USING HINT = 'Insert a verified row into qa_ab_seed_reveals first. Storing planted defects before reveal would place the answer key within reach of the panel under audit.',
            ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS qa_ab_seed_reveals_guard ON public.qa_ab_seed_reveals;
CREATE TRIGGER qa_ab_seed_reveals_guard
  BEFORE INSERT ON public.qa_ab_seed_reveals
  FOR EACH ROW EXECUTE FUNCTION public.qa_ab_guard_reveal();

DROP TRIGGER IF EXISTS qa_ab_seeded_defects_guard ON public.qa_ab_seeded_defects;
CREATE TRIGGER qa_ab_seeded_defects_guard
  BEFORE INSERT ON public.qa_ab_seeded_defects
  FOR EACH ROW EXECUTE FUNCTION public.qa_ab_require_reveal();


-- ============================================================
-- Append-only enforcement on every ledger table
-- ============================================================

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'qa_ab_documents',
    'qa_ab_assignments',
    'qa_ab_runs',
    'qa_ab_findings',
    'qa_ab_gate_decisions',
    'qa_ab_seed_keys',
    'qa_ab_seed_reveals',
    'qa_ab_seeded_defects',
    'qa_ab_finding_scores',
    'qa_ab_execution_outcomes'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t || '_append_only', t);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.qa_ab_append_only()',
      t || '_append_only', t
    );
  END LOOP;
END $$;


-- ============================================================
-- Derived metrics — every number below is computed, never stored
-- ============================================================

-- Catch rate per arm, per defect class, with the fluent-error class
-- separable. Reported as raw counts alongside the rate: the pool is
-- small, and a rate on four defects should not be read like a rate on
-- four hundred.
CREATE OR REPLACE VIEW public.qa_ab_catch_rates AS
WITH planted AS (
  SELECT
    r.id            AS run_id,
    a.arm           AS arm,
    doc.doc_class   AS doc_class,
    d.defect_class  AS defect_class,
    d.is_fluent_error,
    d.id            AS defect_id
  FROM public.qa_ab_seeded_defects d
  JOIN public.qa_ab_seed_keys k    ON k.id = d.seed_key_id
  JOIN public.qa_ab_documents doc  ON doc.id = k.document_id
  JOIN public.qa_ab_assignments a  ON a.document_id = k.document_id
  JOIN public.qa_ab_runs r         ON r.assignment_id = a.id
),
caught AS (
  SELECT DISTINCT
    f.run_id,
    s.seeded_defect_id
  FROM public.qa_ab_finding_scores s
  JOIN public.qa_ab_findings f ON f.id = s.finding_id
  WHERE s.verdict = 'catch'
)
SELECT
  p.arm,
  p.doc_class,
  p.defect_class,
  p.is_fluent_error,
  COUNT(*)                                        AS defects_planted,
  COUNT(c.seeded_defect_id)                       AS defects_caught,
  ROUND(
    COUNT(c.seeded_defect_id)::numeric
      / NULLIF(COUNT(*), 0),
    3
  )                                               AS catch_rate
FROM planted p
LEFT JOIN caught c
       ON c.run_id = p.run_id
      AND c.seeded_defect_id = p.defect_id
GROUP BY p.arm, p.doc_class, p.defect_class, p.is_fluent_error;


-- Verified-by mix among HIGH findings.
--
-- A rising judgment_only share means an anchored arm is degrading toward
-- an unanchored one: it is still producing confident findings, but fewer
-- of them are backed by anything outside the panel.
CREATE OR REPLACE VIEW public.qa_ab_verified_by_mix AS
SELECT
  a.arm,
  f.verified_by,
  COUNT(*)                                                        AS finding_count,
  ROUND(
    COUNT(*)::numeric
      / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY a.arm), 0),
    3
  )                                                               AS share
FROM public.qa_ab_findings f
JOIN public.qa_ab_runs r        ON r.id = f.run_id
JOIN public.qa_ab_assignments a ON a.id = r.assignment_id
WHERE f.severity = 'HIGH'
GROUP BY a.arm, f.verified_by;


-- Calibration and cost per arm.
--
-- known_good_acceptance_rate is the guard against reading harshness as
-- rigour: an arm that rejects work known to have executed cleanly is
-- producing a weak signal, however impressive its catch rate looks.
-- contaminated_runs counts documents where both arms shared a context,
-- which invalidates the pairing rather than merely weakening it.
CREATE OR REPLACE VIEW public.qa_ab_calibration AS
WITH runs AS (
  SELECT
    a.arm,
    r.id AS run_id,
    doc.pool,
    r.wall_clock_seconds,
    r.token_spend,
    g.decision
  FROM public.qa_ab_runs r
  JOIN public.qa_ab_assignments a       ON a.id = r.assignment_id
  JOIN public.qa_ab_documents doc       ON doc.id = a.document_id
  LEFT JOIN public.qa_ab_gate_decisions g ON g.run_id = r.id
),
contaminated AS (
  SELECT a.document_id, r.context_id
  FROM public.qa_ab_runs r
  JOIN public.qa_ab_assignments a ON a.id = r.assignment_id
  WHERE r.context_id IS NOT NULL
  GROUP BY a.document_id, r.context_id
  HAVING COUNT(DISTINCT a.arm) > 1
)
SELECT
  runs.arm,
  COUNT(*)                                                          AS total_runs,
  COUNT(*) FILTER (WHERE runs.pool = 'known_good')                  AS known_good_runs,
  ROUND(
    COUNT(*) FILTER (
      WHERE runs.pool = 'known_good' AND runs.decision = 'APPROVED'
    )::numeric
      / NULLIF(COUNT(*) FILTER (WHERE runs.pool = 'known_good'), 0),
    3
  )                                                                 AS known_good_acceptance_rate,
  ROUND(
    COUNT(*) FILTER (
      WHERE runs.decision = 'APPROVED'
        AND EXISTS (
          SELECT 1 FROM public.qa_ab_execution_outcomes eo
           WHERE eo.run_id = runs.run_id
             AND eo.outcome <> 'clean'
        )
    )::numeric
      / NULLIF(COUNT(*) FILTER (WHERE runs.decision = 'APPROVED'), 0),
    3
  )                                                                 AS approved_then_failed_rate,
  ROUND(AVG(runs.wall_clock_seconds), 1)                            AS avg_wall_clock_seconds,
  ROUND(AVG(runs.token_spend), 0)                                   AS avg_token_spend,
  (SELECT COUNT(*) FROM contaminated)                               AS contaminated_documents
FROM runs
GROUP BY runs.arm;


-- The stopping rule, as a query rather than a judgment call.
--
-- Below the minimum sample the ledger is a log, not evidence, and this
-- view says so in a column instead of leaving it to whoever is reading
-- the numbers on a given afternoon.
CREATE OR REPLACE VIEW public.qa_ab_evidence_status AS
WITH audits AS (
  SELECT
    a.arm,
    r.id           AS run_id,
    d.defect_class
  FROM public.qa_ab_runs r
  JOIN public.qa_ab_assignments a  ON a.id = r.assignment_id
  JOIN public.qa_ab_seed_keys k    ON k.document_id = a.document_id
  JOIN public.qa_ab_seed_reveals rv ON rv.seed_key_id = k.id AND rv.verification_ok
  JOIN public.qa_ab_seeded_defects d ON d.seed_key_id = k.id
)
SELECT
  arm,
  COUNT(DISTINCT run_id)       AS seeded_audits,
  COUNT(DISTINCT defect_class) AS defect_classes,
  CASE
    WHEN COUNT(DISTINCT run_id) >= 8 AND COUNT(DISTINCT defect_class) >= 3
      THEN 'sufficient'
    ELSE 'insufficient_evidence'
  END                          AS evidence_status
FROM audits
GROUP BY arm;


-- ============================================================
-- Access control
-- ============================================================
--
-- RLS is enabled with a service_role policy, matching the pattern used by
-- the other OB1 sidecar schemas. Note what carries the real isolation
-- here: these tables are not exposed through the Open Brain MCP tool
-- surface, which reads and writes public.thoughts only. An agent holding
-- the Open Brain connector cannot reach a seed key through it. Do not
-- add these tables to a shared MCP server without re-reading the reveal
-- gates above, since a tool that can query qa_ab_seeded_defects hands the
-- answer key to the panel being audited.
--
-- The GRANTs are deliberately SELECT and INSERT only. Append-only is
-- enforced twice: by privilege, and by trigger for roles that bypass RLS.

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'qa_ab_documents',
    'qa_ab_assignments',
    'qa_ab_runs',
    'qa_ab_findings',
    'qa_ab_gate_decisions',
    'qa_ab_seed_keys',
    'qa_ab_seed_reveals',
    'qa_ab_seeded_defects',
    'qa_ab_finding_scores',
    'qa_ab_execution_outcomes'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_service_role_rw', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO service_role USING (true) WITH CHECK (true)',
      t || '_service_role_rw', t
    );
    EXECUTE format('GRANT SELECT, INSERT ON TABLE public.%I TO service_role', t);
  END LOOP;
END $$;

GRANT SELECT ON public.qa_ab_catch_rates      TO service_role;
GRANT SELECT ON public.qa_ab_verified_by_mix  TO service_role;
GRANT SELECT ON public.qa_ab_calibration      TO service_role;
GRANT SELECT ON public.qa_ab_evidence_status  TO service_role;

GRANT EXECUTE ON FUNCTION public.qa_ab_commitment(TEXT, TEXT) TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
