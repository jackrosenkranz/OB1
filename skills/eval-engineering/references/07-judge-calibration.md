# Calibrating the Judge

A judge is an instrument, and an uncalibrated instrument drifts without
announcing it. Everything in `02-judge-design.md` is about building a judge
that starts out sound. This file is about proving it stayed sound, and it
supersedes the lighter checks referenced there.

The four mechanisms below come from panel-review practice, where the same
problem was hit earlier and harder. Each one replaces something weaker.

## 1. The seeded-error audit

**Replaces:** the two-case verifier self-test (one correct result, one
plausible-but-wrong result). That check catches a rubric that is backwards. It
does not measure anything.

A seeded audit measures the judge's false-negative rate against defects whose
ground truth the judge never sees.

Recipe:

1. Take a real artifact that has already been reviewed and is believed good.
2. Make a mutated copy with **k = 3 to 6 planted defects**, drawn from at least
   **3 different classes**:
   - a wrong current-year figure, off by a plausible amount
   - a wrong or transposed identifier, citation, or version
   - an off-by-one date, deadline, or boundary
   - a non-idempotent step described as safe to re-run
   - a rollback or recovery path that cannot actually execute, because it
     references something the plan never creates
   - a broken lineage or revision chain
   - **a plausible-but-wrong claim written fluently.** Make it read well. This
     class is the point of the whole exercise.
3. Seal the key. Record what was planted and where, somewhere the judge cannot
   reach. Do not tell the judge the artifact is seeded; the audit is blind by
   design, and saying so changes behavior.
4. Run the judge. Score against the key only after the run is recorded.

Rules that keep the audit honest:

- Do not reuse a seeded artifact for a judge that has already seen it.
- Do not draw the seeded defects only from one judge's known misses. That turns
  a comparison into an attack on one side.
- A finding that turns out to describe a real defect you did not plant is a
  catch, not a false positive. Verify before scoring it as either.

**Report the fluent-but-wrong class separately from everything else.** A judge
that scores plausibility will do fine on transposed digits and badly on the
fluent class. If those two numbers do not separate, whatever anti-plausibility
mechanism the judge claims is not doing anything.

## 2. The known-good set, and acceptance rate

**Replaces:** nothing. This was missing, and its absence is how a bad judge
passes for a good one.

Keep 5 to 10 artifacts known to have executed cleanly. Run them through the
judge alongside everything else.

A judge that rejects work known to be good is **over-harsh, which makes its
signal weak, not strong.** This is the failure mode that looks most like
rigour from the outside, and catch rate alone will never reveal it. A judge
that flags everything has a perfect catch rate.

Track acceptance rate on the known-good set as a first-class number, next to
catch rate, always. Neither means much alone.

This also gives you a replacement rule with teeth. A revised rubric replaces
the incumbent only if it **catches strictly more of the seeded and failed-in-
production pool while approving no fewer of the known-good set.** Ties keep the
incumbent. Without the second half of that sentence, every revision that
increases harshness looks like an improvement.

## 3. `verified_by` as the faithfulness metric

**Replaces:** faithfulness as a score the judge assigns. Tag every finding
instead:

| Tag | Meaning |
| --- | --- |
| `executed` | a script, test, or dry run produced this result |
| `source_fetched` | a figure or citation was retrieved from a real source |
| `judgment_only` | the judge reasoned its way there and nothing outside it confirmed anything |

Two rules follow:

- A `judgment_only` finding cannot be the sole basis for blocking, and cannot
  close a high-severity item. It can raise one.
- **The mix is the drift signal.** Track the share of high-severity findings
  closed by `executed` or `source_fetched` over time. A rising `judgment_only`
  share means the judge is still producing confident output while quietly
  losing its grounding. That is the same failure as a 32% faithfulness score
  behind an 84% quality score, caught by a mechanism instead of an incident.

This is what "measure faithfulness" means operationally. A model asked to rate
its own groundedness is not a measurement.

## 4. The revision counter, as a block rather than a warning

**Replaces:** the drift warning in `02-judge-design.md`, which told you to
watch for optimization against the judge but gave you nothing to enforce.

Resubmitting until approved inflates a pass rate without improving the work.
Count the rounds per artifact:

- **Round 1 or 2:** normal gate.
- **Round 3 and beyond:** a pass is suspect in proportion to the number of
  prior failures. Every high-severity item flagged in any previous round must
  close via `executed` or `source_fetched`. A re-read cannot close it, however
  convincing the re-read is.

The counter has to be recorded, not remembered. An unlogged round count resets
every time somebody opens a new session, which is exactly when it matters.

## Where this lives

All four mechanisms produce facts that only mean something in aggregate and
over time, which makes a chat log or a scratch file the wrong home.
[`schemas/qa-ab-ledger`](../../../schemas/qa-ab-ledger/) is the OB1 store built
for it: append-only tables for runs, findings, seeded defects, and outcomes,
with catch rate, the `verified_by` mix, and known-good acceptance rate as
derived views rather than stored numbers.

It also seals the seed key as a hash commitment and refuses to record the
planted defects until every assigned run is in, which enforces step 1's "keep
it where the judge cannot reach" as a database constraint rather than a
discipline.

One honest limit, worth stating to anyone who adopts this: sealing the key
stops an agent from reading it. It does not stop a person from being in the
same conversation where the key was written. Run the judge in its own context.
