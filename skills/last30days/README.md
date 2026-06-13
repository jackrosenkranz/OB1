# Last 30 Days

> Standalone skill pack that turns the last 30 days of your Open Brain memory
> into a monthly retrospective — themes, momentum, stalls, and what to carry
> forward.

## What It Does

Most second-brain value comes from the periodic re-read, not the capture. This
skill runs that re-read. It pulls your captures from the last 30 days, clusters
them into themes instead of dumping a flat list, and tells you what actually
moved forward, what stalled, which open loops are still open, and what to carry
into next month. When capture tools are available it saves the retrospective
back into Open Brain so each month becomes comparable to the last.

It is inward-facing by design. Unlike [Weekly Signal Diff](../weekly-signal-diff/)
(external market news) or [Daily Digest](../../recipes/daily-digest/) (yesterday's
captures via email), this reads *your own memory* over a full month.

## Supported Clients

- Claude Code
- Codex
- Cursor
- Other AI clients that support reusable prompt packs, rules, or custom
  instructions

## Prerequisites

- Working Open Brain setup ([guide](../../docs/01-getting-started.md))
- AI client that supports reusable skills, rules, or custom instructions
- Open Brain MCP connected so the client can read your last 30 days (and,
  optionally, capture the retrospective back)

## Installation

1. Copy [`SKILL.md`](./SKILL.md) into your client's reusable-instructions
   location.
2. Restart or reload the client so it picks up the skill.
3. Test it with a prompt like:
   `/last30days` or `Run my last 30 days and tell me what moved and what stalled.`

If you want an agent to do the installation for you, copy and paste this:

```text
Install the Last 30 Days skill for me from this repository.

Source file:
- skills/last30days/SKILL.md

What I want you to do:
1. Detect which AI client or agent environment we are in.
2. Create the correct reusable-skill folder for that client.
3. Copy the skill file into that location.
4. Preserve the folder name as `last30days`.
5. Tell me exactly where you installed it.
6. Give me the shortest possible reload step if this client needs one.
7. Give me one test prompt I can run immediately.

If the client has no native skill folder, put the contents somewhere easy to
reuse and tell me exactly how to paste or load it into that client's reusable
instructions feature.
```

For Claude Code, a common install path is:

```bash
mkdir -p ~/.claude/skills/last30days
cp skills/last30days/SKILL.md ~/.claude/skills/last30days/SKILL.md
```

If your client does not support native skill folders, paste the contents of
[`SKILL.md`](./SKILL.md) into that client's reusable prompt or project-rules
feature.

## Trigger Conditions

- "/last30days"
- "Run my last 30 days"
- "Monthly review" / "Do my monthly retrospective"
- "What happened this month?"
- "Recap my last month from my brain"
- "What open loops do I still have from the past month?"
- A recurring end-of-month or start-of-month ritual or scheduled task

## Expected Outcome

When installed and invoked correctly, the skill should produce:

- the exact date window and how many thoughts were read
- a one-line honest summary of the month
- 4-8 themes clustered from the month's captures
- a momentum list (what moved) and a stalls / open-loops list (what didn't)
- the people who recurred and the explicit decisions made
- a diff against last month if a prior retrospective exists
- a short, concrete carry-into-next-month list
- optionally, the retrospective captured back into Open Brain

## Troubleshooting

**Issue: The output is a flat list of every thought**
Solution: The skill should cluster into 4-8 themes, not echo the raw captures.
Re-run and emphasize themes, momentum, and stalls over enumeration.

**Issue: "No thoughts found" for the month**
Solution: Confirm the Open Brain MCP is connected and has recent data. Run
`list_thoughts` manually to verify, and capture a few thoughts before re-running.

**Issue: The month looks incomplete**
Solution: Some clients cap result counts. Ask the skill to raise the limit, and
note that a capped run is a *sampled* retrospective — it should say so.

**Issue: Every month reads as a standalone snapshot**
Solution: Let the skill capture the retrospective back into Open Brain so the
next run can diff against it. The "change from last month" section only appears
when a prior retrospective exists.

## Notes for Other Clients

This skill is portable because the behavior is procedural. Any client that can
load reusable instructions and read your Open Brain memory can run it. Adapt the
Open Brain tool names to the local environment, and for a recurring ritual pair
it with the client's scheduler — keeping the output structure identical every
month so retrospectives stay directly comparable.
