# Eval Task Format

A finding becomes a folder. The folder is the unit the tooling runs, the unit a
reviewer reads, and the unit that survives a model swap.

## Layout

```
evals/<task-id>/
├── task.toml          # metadata, judge pin, rubric line, pass criteria (hidden)
├── instruction.md     # what the agent under test sees
├── environment/       # fixtures, stubbed tools, seeded state (visible)
└── tests/             # the verifier: code checks + judge call (hidden)
```

One capability per folder. If the task name needs an "and", split it.

## Visible vs hidden

| Visible to the agent under test | Hidden from it |
| --- | --- |
| `instruction.md` | expected outcome |
| `environment/` | rubric line |
| the tools it would have in production | judge identity and version |
| | the verifier code |

That separation is the only reason the score means anything. An agent that can
read the rubric optimizes against the rubric.

## Naming and metadata

Give `task.toml` at minimum:

- `id` — stable, referenced from the Open Brain failure record
- `capability` — the one thing under test, in a short phrase
- `origin_trace` — which real failure this came from
- `dataset_type` — `final_response`, `single_step`, `trajectory`, or `rag`
- `judge` — pinned model version, or `none` for pure-code verification
- `rubric` — the single `Pass iff …` line

## The three rules that stop the common failures

### 1. Never treat the recorded answer as truth

The trace tells you what the agent did, never what it should have done. The
answer key comes from one of: a passing test, a source record, written policy,
known system state, or a person who knows. If none of those exist, the task is
not ready to be an eval yet.

### 2. Test the test before trusting it

Run the verifier by hand against one clearly correct result and one plausible
wrong one. Both must land correctly. Re-run this pair after every rubric edit.

That is the minimum bar for a new task. It proves the rubric is not backwards
and proves nothing else. Before trusting a suite's numbers, calibrate the judge
against planted defects it cannot see, per
[07-judge-calibration.md](07-judge-calibration.md).

### 3. Watch for the environment giving away the answer

If the fixture hands over the result before the agent reaches the tool it was
supposed to call, the task passes forever and measures nothing. Check by
running a deliberately broken agent against the task: it must fail. A task no
broken agent can fail is not a test.

## Side effects

Anything that costs money or writes to production gets **simulated, not
called**:

- stub the tool at the boundary and return recorded or hand-written payloads
- include the failure payloads too — empty results, 429s, timeouts, malformed
  responses — since half the starter suite tests behavior under those
- keep fixtures small enough to read in a diff
- no credentials in fixtures, ever; environment variables only

A suite that can be run a hundred times for free is a suite that gets run.

## Speed budget

Hold out **300–800 cases** total and keep a 500-case run under **5 minutes**. A
suite that takes longer than a coffee break stops being run, and a suite that
is not run is worth nothing regardless of how good the rubrics are.
