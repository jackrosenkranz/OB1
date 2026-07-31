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

`public.thoughts` is untouched. The links to it from `qa_ab_documents.thought_id` and `qa_ab_runs.report_thought_id` are optional, nullable, and **deliberately not foreign keys**, for two reasons:

- An audit row must outlive the note that describes it. A ledger entry that disappears along with its description is not a ledger entry. `schemas/thought-audit` makes the same deliberate choice for the same reason.
- `public.thoughts` is not always a base table. On a deployment where it is a view over another schema's table, Postgres rejects a foreign key to it outright (`referenced relation "thoughts" is not a table`). A plain UUID column works whether `thoughts` is a table, a view, or lives elsewhere.

For the same reason, the existence guard checks `pg_class` rather than `information_schema.tables`, which silently counts views as tables.

## Contaminated Runs (1.1.0)

A review can be compromised in ways that have nothing to do with the panel: it sees material it should not have, it runs in a directory full of unrelated context, two arms share a session. Those runs still have to be recorded, because the reveal gate requires a run for every assignment, and because discarding inconvenient data is how a ledger stops being evidence.

So `qa_ab_runs` carries `contaminated` and `contamination_reason`, and a `CHECK` forces the reason whenever the flag is set — a bare flag decays into folklore inside a month. `catch_rates`, `verified_by_mix` and `evidence_status` all exclude contaminated runs, so a biased run can never count toward the 8-audit threshold. `calibration` keeps counting them in `contaminated_runs` / `countable_runs`, so they stay visible rather than silently vanishing.

`notes` holds caveats that belong with the numbers: cost instrumentation limits, dispatch irregularities, anything a reader needs in order to interpret the row.

## Known Gaps

Found by operating the ledger rather than designing it. Both are real and neither is fixed:

- **No way to void an assignment.** The reveal gate requires a recorded run for every assignment. If an arm is dispatched wrongly and you decide not to record it, that audit deadlocks — the reveal is refused forever and the other arm's findings can never be scored. There is no event that distinguishes "not run yet" from "deliberately voided, with a reason."
- **No addendum mechanism for a run.** Provenance discovered after a run is recorded has nowhere to go, because the row can never be updated. Findings, gate decisions and outcomes each got their own table precisely because facts arrive late; a run's own provenance did not.

Both want a small append-only sidecar table. Until then, late-discovered provenance lives outside the ledger, which is the fragility this schema exists to remove.

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

**Issue: `referenced relation "thoughts" is not a table`**
Solution: fixed in 1.0.1. If you are running an older copy, your `public.thoughts` is a view over a table in another schema, and the migration was trying to hang a foreign key off it. Pull the current `schema.sql`, in which `thought_id` and `report_thought_id` are plain UUID columns with no reference.

**Issue: `role "service_role" does not exist` when running the migration outside Supabase**
Solution: the GRANT statements target Supabase's built-in `service_role`. On a plain Postgres instance, create the role first with `CREATE ROLE service_role;` or strip the access-control block at the end of the migration.

**Issue: catch rates look implausibly high**
Solution: check whether the answer key was reachable during review. Query `qa_ab_seed_reveals` and compare `revealed_at` against the `completed_at` of every run on that document. If a reveal predates a run, that audit is contaminated and its rows should be excluded rather than explained.

## Notes

The seeded-defect reveal gate defends against an agent reading the key from the database. It does not defend against a human being in the same conversation where the key was written, and no schema can. Run each arm in its own context.
