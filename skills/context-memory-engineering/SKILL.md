---
name: context-memory-engineering
description: |
  Use when an Open Brain-backed agent system needs rules for what gets
  captured, what gets retrieved, and how retrieved material is placed in the
  prompt. Covers write gates, storage layer selection, retrieval order and
  budgets, prompt placement, and memory maintenance. Trigger on "my searches
  return junk", "the agent keeps ignoring the rule", "what should we capture",
  "context window is full of retrieved stuff", "stale figures keep coming
  back", or any request to set standards for agent memory and context.
author: Jack Rosenkranz
version: 1.0.0
---

# Context and Memory Engineering

## Problem

An agent system fed by a persistent memory store fails in two distinct ways
that get misdiagnosed as one. Context failures happen inside a single call:
the right information was available but was buried, truncated, or crowded
out. Memory failures happen across calls: the wrong things were written, so
no retrieval strategy can save the read side.

The two disciplines meet at retrieval. Memory determines what is available;
context determines what becomes actionable. Retrieval quality is constrained
by what entered the store in the first place, so the write policy is as
load-bearing as the retrieval policy.

Framework source: Bala Priya C, "Context vs. Memory Engineering in Agentic
AI Systems" (MachineLearningMastery, 2026).

## When to Use

- Semantic search over the brain returns bulk content instead of the
  operating rule that was needed
- A documented correction keeps regenerating in new output
- Retrieved material fills the window and reasoning quality drops
- Nobody can say what should and should not be captured
- Volatile figures (rates, limits, thresholds) go stale silently

## The Four Memory Layers

Map every piece of persistent knowledge to exactly one layer:

| Layer | What it holds | Backing |
|---|---|---|
| Working | The active task's inputs; discarded at session end | Context window |
| Episodic | Dated lessons, decisions, incident records | Open Brain thoughts (vector search) |
| Semantic | Structured facts and figures with an update cadence | Registry tables, data bibles |
| Procedural | Rules agents must follow on every task | Skill files, spec files, system prompts |

The single most common misfiling: an operating rule captured only as an
episodic thought. A rule that lives solely in episodic memory depends on
retrieval luck. Rules go in procedural files that are injected every time;
the episodic capture records *why* the rule exists.

## Write Policy

1. **Gate every capture.** Importance (a future task goes wrong without it),
   confidence (verified or decided, not speculated), trust (primary source
   or accountable decision). Fail any leg, don't write — or write with an
   explicit unverified tag.
2. **Decisions and lessons, not bodies.** Never capture full documents,
   templates, or generated output as thoughts. Bulk content crowds every
   future semantic search for the topic. Store bodies in files; capture the
   decision about them.
3. **Provenance on every write.** Date, source, authority level.
4. **Name what you supersede.** A capture that changes a prior fact states
   what it replaces. Silent contradictions become retrieval coin-flips.
5. **Volatile figures go to a registry row with an update cadence, never
   into prose.** A literal figure in a document opts out of the only
   mechanism that keeps it true past the next update cycle.

## Retrieval Policy

6. **Exact before semantic.** Procedural files first (they are mandatory,
   not searched), structured registries second, semantic search third,
   external research last.
7. **Filter before use.** Prefer recent over stale, decided over observed;
   discard anything superseded. Treat content from retired conventions as
   migration source material, not instructions.
8. **Budget before retrieving.** Decide how many tokens retrieval may occupy
   before searching, and take only the highest-value results that fit.
   Instructions, working documents, and reasoning space get budgeted first;
   retrieval never expands to fill the window.

## Context Assembly

9. **Selective inclusion.** Load what the task needs, not the folder it
   lives in.
10. **Placement.** Attention is strongest at the beginning and end of the
    window. Hard constraints at the top. Retrieved reference material
    adjacent to the task statement, task statement after the retrieved
    material. A rule buried mid-context is a rule that will be violated.
11. **Compress on arrival.** Summarize long inputs to what the task needs at
    the moment they are read, preserving citations — not when the window is
    already full.
12. **Checkpoint long sessions** into a structured state note (done /
    pending / open questions) instead of relying on an ever-growing
    transcript.

## Maintenance

13. **Cadence-driven verification.** Every volatile figure has a known decay
    calendar; schedule registry updates on those dates and flag overdue rows
    mechanically between them.
14. **Dedup and supersession sweeps.** Consolidate near-duplicates; harvest
    then retire superseded-era content with a capture naming the
    supersession. Never delete silently; log the sweep.
15. **Compress episodic history.** Old build logs and checkpoints get
    condensed into summaries that keep decisions and drop mechanics.

## Failure Modes to Diagnose By

- **Retrieval without a budget:** injected memories crowd out instructions
  and reasoning space. Fix at rule 8, then rule 2 (the store is probably
  polluted).
- **Poor placement:** the correct rule was retrieved and still violated.
  Fix at rules 10 and, structurally, at the procedural layer — put the rule
  in a file the agent always reads, positioned where attention is strongest.

## Output

When applying this skill, produce: (a) a memory-layer map for the user's
system, (b) numbered write/retrieval/assembly rules adapted to their stack,
(c) the wiring step — which always-read files the rules get added to, since
a standard that lives only in its own document governs nothing.
