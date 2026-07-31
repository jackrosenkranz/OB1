# QA A/B Ledger

> Append-only evidence store for two-arm QA review panels, where the answer key stays sealed until every review is in and every metric is derived rather than recorded.

## What It Does

Adds ten append-only tables and four metric views that record what a QA panel A/B test actually produces: which arm reviewed which document, what each panel found and how it was verified, which planted defects were caught, what the gate decided, and whether approved work later failed in execution.

The design solves a problem that flat files cannot. A seeded-error audit is only valid if the panel never learns which defects were planted, but a markdown answer key in a repo is readable by the same agent being audited. Here the key is sealed as a hash commitment, and the defect rows do not exist in the database until every assigned review has completed and the key has been verified against its commitment.

## Why Not Just Keep Markdown Files

Three properties you get from the table that a file cannot give you:

- **The answer key is unreachable during review.** Open Brain's MCP tool surface reads and writes `thoughts` only, so an agent holding the Open Brain connector cannot reach a sidecar table through it. A file in the working tree is readable by any agent with file access, which includes the panel under audit.
- **History cannot be rewritten.** Append-only is enforced by trigger and by privilege, not by a note saying "never edit history." Facts that arrive later, such as a gate decision or a score, are new rows in their own tables rather than edits to old ones.
- **Metrics cannot drift from the evidence.** Catch rate is defects caught over defects planted. Storing that number next to the raw audits creates two sources of truth that can disagree. Every metric here is a view computed on read.

## Prerequisites

- Working Open Brain setup with the `thoughts` table ([guide](../../docs/01-getting-started.md))
- `pgcrypto` (the migration enables it; already present in a standard Open Brain project)
- Familiarity with Row Level Security if you plan to expose these tables to anything beyond the service role ([primitive](../../primitives/rls/))
- A two-arm review process to measure. This schema records evidence about a QA panel; it does not perform reviews.

## Credential Tracker

Copy this block into a text editor and fill it in as you go.

```text
QA A/B LEDGER -- CREDENTIAL TRACKER
--------------------------------------

SUPABASE (from your Open Brain setup)
  Project URL:           ____________
  Secret key:            ____________

SEED KEY HANDLING (never stored in the database before reveal)
  Where plaintext keys live: ____________
  Who holds them:            ____________

--------------------------------------
```

## Steps

1. Open your Supabase SQL Editor.

2. Paste and run [`schema.sql`](schema.sql). It is idempotent, so running it twice is safe.

3. Verify the objects exist:

   ```sql
   SELECT table_name FROM information_schema.tables
    WHERE table_name LIKE 'qa\_ab\_%' AND table_type = 'BASE TABLE'
    ORDER BY table_name;
   ```

   You should see ten tables.

4. Run [`verify.sql`](verify.sql) to prove the guard rails actually hold. It runs inside a transaction and rolls back, so it leaves no rows behind:

   ```bash
   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f verify.sql
   ```

   Every assertion should read `PASS`.

5. Seal your first audit. Generate the commitment *outside* any context that will later run a review, and keep the plaintext key somewhere the review agent cannot read:

   ```sql
   SELECT public.qa_ab_commitment('<random salt>', '<full plaintext key>');
   ```

6. Record the document, the seal, and the arm assignments. Run the reviews. Record each run when it completes.

7. Reveal only after every assigned run is recorded. Insert the reveal row with `verification_ok` set to whether the plaintext key hashed back to the stored commitment, then insert the defect rows.

8. Read the metrics:

   ```sql
   SELECT * FROM public.qa_ab_evidence_status;
   SELECT * FROM public.qa_ab_catch_rates ORDER BY arm, defect_class;
   SELECT * FROM public.qa_ab_verified_by_mix ORDER BY arm;
   SELECT * FROM public.qa_ab_calibration;
   ```

## Expected Outcome

After step 3, ten tables (`qa_ab_documents`, `qa_ab_assignments`, `qa_ab_runs`, `qa_ab_findings`, `qa_ab_gate_decisions`, `qa_ab_seed_keys`, `qa_ab_seed_reveals`, `qa_ab_seeded_defects`, `qa_ab_finding_scores`, `qa_ab_execution_outcomes`) and four views (`qa_ab_catch_rates`, `qa_ab_verified_by_mix`, `qa_ab_calibration`, `qa_ab_evidence_status`).

After step 4, nine `PASS` lines confirming that defects are rejected before reveal, that reveal is blocked while a review is outstanding, that a tampered key fails its commitment, that updates to ledger tables are refused, and that the views reproduce a known arm separation from recorded rows alone.

After step 8, `qa_ab_evidence_status` reports `insufficient_evidence` until an arm has at least 8 seeded audits across at least 3 defect classes. That is the point: the stopping rule is a column rather than a judgment call made by whoever is reading the numbers that afternoon.

`public.thoughts` is untouched. Links to it from `qa_ab_documents` and `qa_ab_runs` are optional and nullable.

## What Each Metric Is Guarding Against

- `qa_ab_catch_rates` splits out `is_fluent_error`, the plausible-but-wrong defect class. A panel that scores how right something *sounds* is predicted to miss exactly this class. If two arms do not separate here, whatever anchoring mechanism one of them claims is not doing its job.
- `qa_ab_verified_by_mix` tracks the share of HIGH findings closed by `executed` or `source_fetched` rather than `judgment_only`. A rising judgment-only share means an anchored arm is quietly degrading into an unanchored one while still producing confident output.
- `qa_ab_calibration` reports acceptance rate on the known-good pool. An arm that rejects work known to have executed cleanly is over-harsh, which makes its signal weak rather than strong. It also counts `contaminated_documents`, where both arms shared a `context_id` on the same document and the pairing is therefore void.
- `qa_ab_evidence_status` refuses to let a small sample read as a result.

## Troubleshooting

**Issue: `no verified reveal exists for seed key ...` when inserting defects**
Solution: working as designed. Insert a row into `qa_ab_seed_reveals` with `verification_ok = true` first. If you are trying to record defects before the reviews have run, stop: that places the answer key in the database while the audit is live, which is the failure this schema exists to prevent.

**Issue: `N assigned review(s) have not completed for this seed key`**
Solution: every assignment for the document needs a corresponding row in `qa_ab_runs` before the reveal is allowed. If an arm was assigned but never actually ran, record the run with its real timings anyway, or the audit is not paired and should not be scored as if it were.

**Issue: `qa_ab_findings is append-only`**
Solution: also working as designed. To correct a finding, insert a new one and record the correction in `rationale` on its score row. To change a gate decision, insert a new run for the next revision round. Nothing in this schema supports editing history, because the metrics are only trustworthy if the facts underneath them are immutable.

**Issue: `role "service_role" does not exist` when running the migration outside Supabase**
Solution: the GRANT statements target Supabase's built-in `service_role`. On a plain Postgres instance, create the role first with `CREATE ROLE service_role;` or strip the access-control block at the end of the migration.

**Issue: catch rates look implausibly high**
Solution: check whether the answer key was reachable during review. Query `qa_ab_seed_reveals` and compare `revealed_at` against the `completed_at` of every run on that document. If a reveal predates a run, that audit is contaminated and its rows should be excluded rather than explained.

## Notes

The seeded-defect reveal gate defends against an agent reading the key from the database. It does not defend against a human being in the same conversation where the key was written, and no schema can. Run each arm in its own context.
