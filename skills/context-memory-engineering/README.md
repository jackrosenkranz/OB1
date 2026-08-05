# Context and Memory Engineering

> Reusable skill pack that gives an Open Brain-backed agent system explicit rules for what gets written to memory, what gets retrieved, and where retrieved material lands in the prompt.

## What It Does

Context engineering and memory engineering solve different problems — one
governs a single inference call, the other governs what persists between
calls — and they meet at retrieval, where stored knowledge either becomes
actionable or becomes noise. This skill teaches an AI client to:

- Map a system's knowledge onto four memory layers (working, episodic,
  semantic, procedural) and file each piece in exactly one
- Gate every Open Brain capture on importance, confidence, and trust, with
  provenance and named supersession
- Retrieve exact-before-semantic, filter before use, and set a token budget
  before searching
- Assemble context deliberately: hard constraints at the top, retrieved
  material adjacent to the task, long inputs compressed on arrival
- Maintain the store: cadence-based figure verification, dedup and
  supersession sweeps, episodic compression

It also names the two retrieval-boundary failure modes worth diagnosing by:
retrieval without a context budget, and correct-but-badly-placed rules that
keep getting violated.

Framework source: Bala Priya C, "Context vs. Memory Engineering in Agentic
AI Systems" (MachineLearningMastery, 2026). The rules here were battle-tested
against a 186-item legal document production system running on Open Brain,
where both failure modes occurred in production before these rules existed.

## Supported Clients

- Claude Code
- Claude Desktop and other Anthropic-style skill systems
- Codex, Cursor, or any client that reads a skill/rules file

## Prerequisites

- Working Open Brain setup ([guide](../../docs/01-getting-started.md))
- An agent workflow that captures to and retrieves from the brain

## Installation

1. Copy this folder somewhere your AI client reads skills from. For Claude
   Code:

   ```bash
   mkdir -p ~/.claude/skills/context-memory-engineering
   cp -R skills/context-memory-engineering/* ~/.claude/skills/context-memory-engineering/
   ```

2. Reload the client.
3. Verify with: `Use the context-memory-engineering skill. Map my system's
   memory layers and draft write, retrieval, and assembly rules for it.`

## Usage Pattern

Point the skill at a real symptom, not at the abstract topic:

- "Semantic search keeps returning old template bodies instead of the rule
  I need" → write-policy and sweep rules
- "The agent had the correction in context and still violated it" →
  placement and procedural-layer wiring
- "Retrieved memories eat half my window" → retrieval budget

The skill's final step is always the wiring step: the produced rules get
added to the files the agent actually reads on every task. A standard that
lives only in its own document governs nothing.
