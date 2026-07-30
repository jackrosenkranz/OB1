# Verdict Routing and the Confidence Gate

A score that never changes behavior is analytics. An eval that changes the next
edge is engineering.

## Six verdicts, six structural actions

Each verdict does something to the run **in progress**, not to a report read
next quarter.

| Verdict | Action | Why this one |
| --- | --- | --- |
| Low context recall | Reject the handoff | The next node would build on a gap |
| Bad tool use | Retry, or swap the node | Wrong tool or wrong arguments is recoverable in place |
| Hallucination | Quarantine the branch | Nothing downstream of an invention is trustworthy |
| Schema failure | Block the edge | A malformed contract corrupts every consumer |
| Compliance risk | Route to human review | The only verdict whose action is a person |
| Verified completion | Terminate the run | Done means a real signal says done, never the agent's own word |

Implementation notes:

- Bound the retries. Two attempts on the same node, then escalate — an
  unbounded retry on a deterministic failure is just a slower outage.
- Quarantine means the branch's output is withheld from downstream nodes and
  the run continues without it or halts. It does not mean "log a warning".
- Log every routing action with the verdict that caused it. That log is the
  track record the confidence gate later reads.

## The confidence gate

Once the routing works, the same machinery decides whether work can ship
unattended. When an agent opens a pull request, four signals are already
available:

1. **Guardrails result** — a deterministic pass/fail on blocking standards. No
   model involved.
2. **Recent eval trajectory** — how this exact version of this agent has been
   scoring lately.
3. **Historical revert rate** — how often this agent, on this repo, on this
   class of change, has had work rolled back.
4. **Sandbox outcome** — did it actually run.

Three of the four are history and deterministic checks. Exactly one touches the
model. Trust in an agent is an actuarial calculation, and it sharpens every
week whether or not the models improve.

Above the threshold, the change merges itself. Below it, a human gets it **with
the failing signal named**, so the review starts at the problem instead of at
line one.

The constraint is the product. The reason this works is not that the agent is
trusted; it is that the space it can act in is small enough to verify.

## Rolling it out safely

1. **Shadow first.** The gate scores every change and merges none, for at least
   4 hours of real traffic — longer if traffic is thin.
2. **Deviation threshold of 2%.** If the automated verdict and the human
   verdict disagree more than that, the gate stays closed.
3. **Sample traces at 1%–5%** once live. Full capture is a cost with no
   matching signal.
4. **Start with the boring slice.** Open the gate on low-risk change classes and
   keep it closed on the risky ones. The value is in the 80% that used to queue
   behind one tired reviewer, not in the 20% that genuinely needs eyes.
5. **Re-close on drift.** A rising revert rate closes the gate automatically;
   do not make that a human decision made under deadline.

## The warning worth more than the formula

A codebase that ran hundreds of self-improving iterations came out with a large
pile of merged changes, zero regressions on the suite — and 38 green tests
coexisting with a completely broken product.

A suite can go all green while the thing it guards falls apart. The loop has to
converge on the spec, not on the score. Keep at least one check that a human
wrote, that reads the product rather than the tests, and that runs before any
claim that the system is healthy.
