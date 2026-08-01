# Judge Design

The examiner needs hygiene of its own, and this is the part almost everyone
sets up wrong.

## Rule 1 — Judge from another family

A model recognizes its own writing and grades it kinder once it does. When the
same family generates and grades, the blind spots are shared: the judge cannot
see the failure mode it would have produced itself.

- Use a different model family for the judge than for the generator.
- If the family must be shared, at minimum use a different size class and
  accept that the numbers are softer than they look.
- Never let an agent grade its own output in the same call.

## Rule 2 — One line, one verdict

The working form is literally:

```
Pass iff [the independently observable successful outcome]
```

*Independently observable* is the load-bearing phrase. If confirming the
outcome requires re-reading the agent's own reasoning, the rubric is circular.

- One primary verdict per eval. Not a bundle of proxy scores averaged into a
  number nobody can act on.
- If the capability genuinely has two outcomes, that is two evals.
- Write the rubric before running anything. A rubric written after seeing
  outputs is a description of what the agent already does.

## Rule 3 — Split the work by kind

| Decide with plain code | Decide with the judge |
| --- | --- |
| Did the test pass | Is the answer grounded in what the tools returned |
| Does the file exist | Is the refusal appropriate rather than evasive |
| Did the state change | Is the summary faithful to the source |
| Was the schema valid | Is the tone right for this user |
| Was the tool called with these arguments | Did the plan address the actual request |

Every objective check pushed into the model is money spent on variance. Every
semantic check pushed into code becomes a brittle string match.

## Rule 4 — Never reward the shape of an answer

Do not score on:

- response length
- keyword presence
- citation count
- exact phrasing
- number of tool calls
- similarity to a reference answer

Reward the shape and the agent learns the shape. An agent optimized against a
length-and-citations rubric produces long, heavily cited, confidently wrong
answers — which is exactly the failure the eval was supposed to catch.

## Rule 5 — Pin the judge and log its version

The one people skip, and the one that makes a month of scores unreadable.

- Pin an explicit model version, not a floating alias.
- Log the judge version, the rubric hash, and the run date with every score.
- When the judge version changes, re-score a held-out sample under both and
  publish the delta before trusting any comparison across the boundary.
- Treat a rubric edit exactly like a judge upgrade: same re-score, same delta.

## Rule 6 — Test the test

Before the verifier grades anything real, hand it two results by hand:

1. one clearly correct
2. one plausible but wrong — the shape of a good answer with a fabricated fact

If either goes the wrong way, the rubric is broken, not the agent. Fix it
before the first real run, and re-run this pair every time the rubric changes.

This is a smoke test, not a measurement. It catches a rubric that is backwards
and nothing subtler. Once the judge is running on real work, replace it with
the seeded-error audit in
[07-judge-calibration.md](07-judge-calibration.md), which measures the judge's
miss rate against defects it never sees.

## Rule 7 — Never let a judgment stand alone at the top

Tag every finding with how it was established: `executed`, `source_fetched`, or
`judgment_only`. A `judgment_only` finding can raise a high-severity item but
cannot close one, and cannot be the sole basis for blocking.

The share of high-severity findings closed by something other than judgment is
the drift metric that matters. See
[07-judge-calibration.md](07-judge-calibration.md).

## Drift watch

Optimize against a judge long enough and the agent learns to look right rather
than be right. Three signals that this is happening:

- scores climb while user complaints hold steady or rise
- the agent's outputs converge on a recognizable house style
- the `judgment_only` share of high-severity findings rises

The first two call for a fresh held-out set drawn from recent traces, not a
rubric tweak. The third means the judge has lost its grounding and needs
executable anchors restored before its scores mean anything again.
