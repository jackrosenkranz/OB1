---
name: eval-engineering
description: |
  Use when the user needs to know whether an AI agent is actually right, not
  just whether it sounds right. Covers mining production traces for real
  failures, turning each failure into a permanent eval, designing a judge that
  cannot be gamed, wiring verdicts back into routing decisions, and gating
  autonomous merges on a confidence score. Trigger on "build evals", "how do I
  measure this agent", "my agent hallucinates", "the demo looks great but
  customers complain", "LLM as judge", "eval harness", "can I let this merge
  itself", or any request where the missing layer is the one that decides
  whether an answer was correct and then does something with the verdict.
author: Jack Rosenkranz
version: 1.0.0
---

# Eval Engineering

## Problem

Everyone rents the same model. The gap between two teams running the identical
model is the layer that decides whether an answer was right and then changes
what runs next.

Most teams own a thermometer: a dashboard, a vibe, a Friday where somebody
scrolls outputs and says it seems worse than last week. Eval engineering is the
thermostat — the wiring that runs from the reading back into the furnace.

The failure this catches looks like a real production case: an agent scored
83.9% on response quality and 32.3% on faithfulness in the same run. The search
tool came back empty, the model filled the hole, and the invented exchange rate
was handed over as a looked-up fact. Nobody caught it because the writing was
the only part anyone ever looked at. A better model would not have caught it
either.

## When to Use

- "Build evals for this agent" / "how do I test an AI system"
- "My agent hallucinates when a tool returns nothing"
- "The demo is great, production is not"
- "Set up an LLM judge" / "which model should grade this"
- "Can this agent merge its own pull requests?"
- The user has traces, logs, or user complaints and no test suite
- The user has a test suite that is all green while the product is broken
- Any multi-agent or graph build where parallel work multiplies the places a
  wrong answer can look finished

## Core Rules

Three lines hold the whole discipline. Repeat them when the user drifts.

1. **Measure the path, not only the answer.** An agent that reaches a correct
   answer through a broken sequence will reach a wrong one tomorrow.
2. **A verdict that does not change the next edge is a report.** Scores that
   only land in a dashboard are analytics, not engineering.
3. **Any failure you do not turn into a permanent test, you will meet again.**

## Required Context

Gather before building anything:

- what the agent is (entrypoint, tools, backing data) and what a good result
  looks like *to the user*, in their words
- access to real runs: traces, logs, transcripts, or ticket history
- which failures have already cost something — money, trust, a rollback
- what the agent is allowed to do (permissions, write access, spend)
- prior eval work, rubrics, or incident notes already stored in Open Brain

If traces are unavailable, say so plainly and build the first eval from the
most recent real complaint instead of from imagination. Never generate a
synthetic suite and present it as coverage.

## Process

### Step 1 — Pull Open Brain context first

Search Open Brain (usually `search_thoughts`) for prior incidents, rubrics,
definitions of correct, and previous eval runs on this system. The definition
of correct lives in the user's head and in their memory store, never in the
model. Carry forward what is already decided instead of re-litigating it.

### Step 2 — Mine traces, do not invent tests

Read [references/01-trace-mining.md](references/01-trace-mining.md).

Pull about 25 complete traces chosen so working and broken behavior sit next to
each other, write each up in four lines, and get attribution right before
proposing anything. Attribution is where a week gets lost: the same lookup
called twice with identical arguments is your loop; a 429 is somebody else's
limit and only becomes your eval if the agent was supposed to recover from it.

### Step 3 — Interview, then propose two or three candidates

Do not one-shot a suite. Present two or three eval candidates grounded in what
actually failed in the traces, recommend one, and wait for the user to choose.
Questioning the user beats generation here, every time, for the plain reason
that only they know what correct means.

### Step 4 — Build the eval and test the test

Read [references/03-eval-task-format.md](references/03-eval-task-format.md).

One capability per folder. Instruction and environment are visible to the agent
under test; expected outcome, rubric, and judge credentials are hidden. Before
the real run, hand the verifier one clearly correct result and one plausible
wrong result by hand. If either goes the wrong way, the rubric is broken, not
the agent.

### Step 5 — Design the judge

Read [references/02-judge-design.md](references/02-judge-design.md).

Judge from a different model family than the one generating. Write the rubric
as one line: `Pass iff [independently observable successful outcome]`. Send the
objective calls to plain code and keep only the semantic calls for the model.
Never reward the shape of an answer. Pin the judge version and log it — an
examiner that silently upgrades makes a month of scores unreadable after the
fact, and nobody notices until they try to compare.

### Step 6 — Wire the verdict into the next edge

Read [references/04-verdict-routing.md](references/04-verdict-routing.md).

Every verdict maps to a structural action on the run in progress:

| Verdict | Action on the run |
| --- | --- |
| Low context recall | Reject the handoff |
| Bad tool use | Retry, or swap the node |
| Hallucination | Quarantine the branch |
| Schema failure | Block the edge |
| Compliance risk | Route to human review |
| Verified completion | Terminate the run |

If the user's design has no path from a verdict back into execution, name that
as the gap before discussing anything else.

### Step 7 — Capture the failure permanently

Write the finding back to Open Brain (usually `capture_thought`): the failing
behavior, the attribution, the eval that now guards it, and the rubric line.
This is the compounding part. The model is a rental and will be replaced twice
this year; the examiner and the failure log are yours and get more valuable
every week.

### Step 8 — Only then, autonomy

If and only if the user asks about autonomous merge or unattended runs, read
[references/04-verdict-routing.md](references/04-verdict-routing.md) for the
confidence-gate pattern and roll it out in shadow mode first. Trust in an agent
is an actuarial calculation over a track record, not a feeling about the model.

## Starter Suite

When the user wants something running this week rather than a program, read
[references/05-starter-suite.md](references/05-starter-suite.md) and give them
three measurements, one dataset type, and five evals. That is an afternoon.
Twelve metrics is a project that never ships.

## Tooling

Read [references/06-tooling.md](references/06-tooling.md) only when the user
asks what to install. A general coding agent plus a plain folder of eval tasks
is a legitimate starting stack; do not send anyone to procurement to get a
first number.

## Guard Rails

- **Never treat a recorded answer as ground truth.** A trace shows what the
  agent did, never what it should have done. Take the answer key from tests,
  source records, policy, known state, or a person.
- **Watch for the environment leaking the answer.** If the setup hands over the
  result before the agent reaches the tool it was supposed to call, the task
  passes forever and measures nothing.
- **Simulate anything that costs money or writes to production**, so the suite
  can run as often as the user likes without a bill or a side effect.
- **Green suites lie.** Thirty-eight passing tests can coexist with a
  completely broken product. Converge on the spec, not on the score.
- **Optimize against a judge long enough and the agent learns to look right
  rather than be right.** Rotate held-out cases and re-check the rubric when
  scores climb without complaints falling.
- **No credentials in eval fixtures.** Use environment variables and redact
  trace payloads before they are stored or committed.
- **Redact before capture.** Production traces carry customer data; strip it
  before writing findings to Open Brain or into a repo.

## Output Contract

For a build request, return:

- what the agent is and what correct means, in the user's words
- the failures found in the traces, with attribution for each
- two or three eval candidates, one recommended, the rest with a reason
- the built eval: folder layout, hidden rubric line, verifier self-test result
- the routing action each verdict triggers
- what got captured to Open Brain

For an audit of an existing setup, return findings first, ordered by leverage:

- metrics that measure shape rather than substance
- judges sharing a family with the generator, or unpinned
- verdicts with no path back into execution
- coverage gaps against the five starter evals
- a prioritized fix sequence with the check that confirms each fix

## Final Check Before Responding

- Did every eval come from a real failure rather than an imagined one?
- Does the path get measured, not just the final answer?
- Does each verdict change something structural about the run?
- Was the verifier tested against one passing and one plausible wrong result?
- Is the judge from a different family, pinned, and version-logged?
- Did the failure get captured so it cannot break the same thing twice?
