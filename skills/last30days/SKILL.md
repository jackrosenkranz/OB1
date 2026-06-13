---
name: last30days
description: |
  Use when the user wants a 30-day retrospective of their own Open Brain memory
  — a monthly review of what they captured, what themes recurred, which open
  loops are still open, and what to carry into the next month. Fires on prompts
  like "/last30days", "run my last 30 days", "monthly review", "what happened
  this month", or "recap my last month from my brain". This is an inward-facing
  memory retrospective, not an external news scan. It reads thoughts from the
  last 30 days, clusters them, surfaces momentum and stalls, and optionally
  captures the retrospective back into Open Brain so months become comparable.
author: Jack Rosenkranz
version: 1.0.0
---

# Last 30 Days

## Problem

Memory accumulates faster than it gets reviewed. Over a month a person captures
dozens of observations, tasks, ideas, references, and person notes — and then
never looks back. The value of a second brain is not capture, it is the
periodic re-read that turns scattered notes into direction. This skill runs that
re-read: it pulls the last 30 days from Open Brain, finds the structure inside
it, and tells the user what actually moved, what stalled, and what deserves
attention next month.

## When to Use

- "/last30days"
- "Run my last 30 days"
- "Monthly review" / "Do my monthly retrospective"
- "What happened this month?" / "Recap my last month from my brain"
- "What open loops do I still have from the past month?"
- A recurring end-of-month or start-of-month ritual or scheduled task

## Required Context

Gather as much as the environment allows before writing:

- the user's captures from the last 30 days (the primary input)
- the user's overall capture profile — totals, dominant types, top topics and
  people — to read the month against the baseline
- the previous month's retrospective if one was captured, so this run can be a
  diff and not a standalone snapshot
- any framing the user gave: a specific project, person, or question they want
  the month read through

Tool names vary by client. Use the Open Brain search, list, stats, and capture
tools available in the environment rather than assuming fixed names. In a
standard Open Brain MCP setup these map to `list_thoughts`, `thought_stats`,
`search_thoughts`, and `capture_thought`.

## Process

1. Frame the window.
   - Default to the last 30 days ending today. If the user names a project,
     person, or question, keep the same window but read everything through that
     lens.
   - State the exact date window in the output so the retrospective is
     reproducible and comparable to other months.

1. Pull the raw month.
   - List thoughts from the last 30 days. Use a generous limit (aim for 100+,
     or the client's max) so the month is not silently truncated.
   - If the client caps results, note that the retrospective is sampled and say
     how many thoughts were read versus how many exist.
   - If there are no thoughts in the window, say so plainly, show the baseline
     stats for context, and stop — do not invent a retrospective.

1. Read the month against the baseline.
   - Pull overall stats (totals, type breakdown, top topics, top people).
   - Compare the month to the baseline: which types over- or under-indexed this
     month, which topics or people spiked, which usual themes went quiet.

1. Cluster instead of list.
   - Group the month's captures into a small number of themes (aim for 4-8),
     not a flat chronological dump.
   - Within each theme, distinguish what changed from what was merely restated.
   - Use semantic search to pull older related context when a theme clearly
     extends something from before the window — but keep the focus on the month.

1. Find the momentum and the stalls.
   - Momentum: themes with repeated captures, decisions reached, ideas that
     turned into tasks, questions that got answered.
   - Stalls: open questions never resolved, tasks captured but never followed
     up, ideas raised once and dropped, recurring frustrations.
   - Open loops: anything still clearly unfinished at the end of the window.

1. Surface the people and decisions.
   - Note who appeared most in person notes and what those interactions were
     about.
   - Pull out explicit decisions made during the month, with the reasoning if it
     was captured.

1. Diff against last month if available.
   - If a prior retrospective exists, label themes as new, continuing, rising,
     fading, or resolved relative to it.
   - If none exists, say this is the first retrospective and set the baseline.

1. Write the retrospective (default structure):
   - `Window` — exact date range, thoughts read vs. total, and how it was framed
   - `The month in one line` — a single honest sentence summarizing it
   - `Themes` — 4-8 clusters, each with what changed and why it matters
   - `Momentum` — what genuinely moved forward
   - `Stalls & open loops` — what is unfinished or dropped, stated without
     softening
   - `People` — who recurred and around what
   - `Decisions` — explicit calls made this month
   - `Change from last month` — only if a prior retrospective exists
   - `Carry into next month` — 3-7 concrete things to pick up, watch, or close

1. Capture the durable output.
   - When capture tools are available, save the retrospective back into Open
     Brain as a single durable record.
   - Include provenance in the content: the date window, "30-day retrospective",
     and the major themes — so next month's run can find and diff against it.
   - Do not spray dozens of separate captures; one durable summary plus, at
     most, a few captures for genuinely important new open loops.

## Output

When this skill works correctly, the user gets:

- a clear 30-day retrospective of their own memory, not a news feed
- themes instead of a flat list of captures
- an honest read on what moved and what stalled
- a short, concrete carry-forward list for the next month
- a durable retrospective saved back to Open Brain so months become comparable

## Guardrails

- This is inward-facing. Do not pull external news or web sources unless the
  user explicitly asks — the input is the user's own memory.
- Never modify or delete existing thoughts. This skill reads and, at most,
  writes one new summary record.
- Do not pad. If the month was thin, say it was thin and keep the output short.
- Do not soften the stalls. The value of the retrospective is naming the open
  loops the user has been avoiding.
- Be explicit about coverage limits when the client truncates results — a
  sampled month must be labeled as sampled.
- Keep general patterns separate from the concrete carry-forward actions.

## Notes for Other Clients

- This skill is portable across Claude Code, Codex, Cursor, and similar clients
  because the behavior is procedural.
- Adapt the Open Brain tool names to whatever the local environment exposes.
- For a recurring ritual, pair it with the client's scheduler (for example a
  monthly scheduled task) and keep the output structure identical every month
  so retrospectives stay directly comparable.
