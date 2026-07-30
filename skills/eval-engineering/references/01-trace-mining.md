# Trace Mining

Tests invented at a desk protect against failures somebody already imagined.
The failures that cost money are sitting in the logs right now, wearing a
timestamp.

## The loop

```
mine traces -> identify a failure -> build an eval -> improve the agent -> rerun
```

The first step carries the weight. Everything downstream inherits its quality.

## How many, and which ones

Pull about **25 complete traces**, not more. The point is not volume, it is
that working and broken behavior sit next to each other in the same sample.
Choose deliberately across these five kinds:

1. **A normal request that finished.** The baseline for what working looks like.
   Without it, every later judgment drifts.
2. **A request the user confirmed.** The rare trace where the answer is known
   good. Treat these as scarce.
3. **A request the user corrected or rephrased.** The correction is a free
   label. A rephrase usually means the first answer was wrong in a way the user
   could not articulate.
4. **A run with a failed, empty, or repeated tool call.** Repetition means a
   loop. Emptiness means an invented answer is about to follow.
5. **A run with an external failure.** A timeout, a 429, a malformed upstream
   payload. The only thing under test is how the agent behaves when the world
   says no.

If the system has permission boundaries or spend limits, add a sixth: a run
where the agent was asked for something outside them.

## The four-line write-up

Every selected trace gets exactly this. Resist the urge to write prose.

```
Observed behavior: what the user asked and what the agent actually did
Comparison:        what worked and what did not
Attribution:       agent behavior, dependency behavior, or unclear
Eval candidate:    the capability to preserve or improve
```

Keep `unclear` as a real option. Forcing an attribution you cannot support
produces an eval that guards the wrong thing.

## Attribution rules

This is where beginners lose a week.

- **Agent behavior.** The same lookup called twice with identical arguments is a
  loop in your graph. An answer more specific than anything the tools returned
  is a fabrication. A handoff that reads a field the previous node never wrote
  is a contract break. All yours.
- **Dependency behavior.** A 429, a timeout, a schema change upstream, an empty
  result set for a query that was correct. Not yours — *unless* the agent was
  supposed to recover, in which case the eval is about the recovery, not the
  failure.
- **Unclear.** Log it, keep the trace, move on. Two more instances usually
  resolve it.

## Sampling in production

- Full capture on every run is a cost nobody needs to carry. Sample **1%–5%** of
  traces once the system is past its first weeks.
- Always capture 100% of runs that ended in an error, a user correction, or a
  rollback. Those are the labeled ones.
- Redact customer data at capture time, not at review time.

## Handoff to Open Brain

For each confirmed failure, capture one record: the observed behavior, the
attribution, the eval that now guards it, and the date. Search this store
before every future mining pass — a failure that reappears after being guarded
means the eval was wrong, which is a much more interesting finding than the
failure itself.
