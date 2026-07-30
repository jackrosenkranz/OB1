# Eval Engineering

> Reusable skill pack for building the layer that decides whether an AI agent was actually right — and then does something with the verdict.

## What It Does

Eval Engineering teaches an AI client to turn real production failures into permanent tests, design a judge that cannot be gamed, and wire each verdict back into the run so a score changes execution instead of landing in a dashboard.

It is an operating procedure, not a framework. The client mines your traces, proposes evals grounded in what actually failed, builds them with the rubric hidden from the agent under test, and captures each failure to Open Brain so the same thing cannot break twice.

## Supported Clients

- Claude Code
- Claude Desktop and other Anthropic-style skill systems
- Codex
- Cursor or any client that can keep a skill file next to a bundled `references/` directory

## Prerequisites

- Working Open Brain setup, so failures and rubrics persist across sessions and tools ([guide](../../docs/01-getting-started.md))
- AI client that supports reusable skill files, project rules, or custom instructions
- Access to real runs of the agent you want to measure: traces, logs, transcripts, or ticket history
- Ability to keep the bundled `references/` directory next to the installed `SKILL.md`

## Installation

1. Copy the entire [`eval-engineering`](./) folder somewhere your AI client reads skills from. Keep `references/` next to `SKILL.md`.
2. For Claude Code, a common install path is:

   ```bash
   mkdir -p ~/.claude/skills/eval-engineering
   cp -R skills/eval-engineering/* ~/.claude/skills/eval-engineering/
   ```

3. Reload or restart the client so it picks up the new skill.
4. Point the client at a folder of real traces, or tell it where your logs live.
5. Verify with a prompt like: `Use the eval-engineering skill. Read the traces in ./traces and propose two or three eval candidates grounded in what actually failed there. Recommend one. Do not implement until I choose.`

✅ **Done when:** the client returns candidates that quote specific traces, rather than a generic list of eval categories.

## Trigger Conditions

- "Build evals for this agent"
- "How do I measure whether this agent is right?"
- "My agent invents answers when the search comes back empty"
- "The demo looks great but customers keep complaining"
- "Set up an LLM judge" / "which model should grade this?"
- "Can I let this agent merge its own pull requests?"
- The user has a green test suite and a broken product
- The user has traces and no idea which ones matter

## Expected Outcome

When installed and invoked correctly, the skill produces:

- a short list of real failures pulled from real traces, each with an attribution (agent, dependency, or unclear)
- two or three eval candidates, one recommended, with reasons for the rest
- a built eval as a self-contained task folder, with the expected outcome, rubric, and judge credentials hidden from the agent under test
- a verifier that has been tested against one clearly correct and one plausible-but-wrong result before its first real run
- a mapping from each verdict to a structural action on the run: reject the handoff, retry or swap the node, quarantine the branch, block the edge, route to human review, terminate the run
- an Open Brain record for each failure, so the next mining pass starts from what is already known

## Troubleshooting

**Issue: The client generates a suite of plausible-sounding evals with no connection to anything that happened**
Solution: It has no traces. Give it a folder of real runs, or the text of a recent complaint. The skill is explicit that invented tests only guard imagined failures — if you skip the input, that guard rail has nothing to work with.

**Issue: Scores climb every week and users complain just as much**
Solution: The agent is optimizing against the judge's shape rather than being correct. Check the rubric against the "never reward the shape of an answer" list in [`references/02-judge-design.md`](references/02-judge-design.md), and draw a fresh held-out set from recent traces instead of tweaking the rubric.

**Issue: Every eval passes, including ones that should be impossible**
Solution: The environment is leaking the answer. Run a deliberately broken agent against the task — if it passes, the fixture is handing over the result before the agent reaches the tool it was supposed to call. See [`references/03-eval-task-format.md`](references/03-eval-task-format.md).

**Issue: The suite stopped being run**
Solution: It got too slow. Hold out 300–800 cases and keep 500 running in under five minutes. A suite that takes longer than a coffee break is a suite nobody runs.

**Issue: Scores before and after a date are not comparable and nobody knows why**
Solution: The judge upgraded silently. Pin an explicit model version, log it with every score, and re-score a held-out sample under both versions before comparing across the boundary.

## Notes for Other Clients

The root [`SKILL.md`](./SKILL.md) is the portable version. It references Open Brain tools by their common names (`search_thoughts`, `capture_thought`); connector prefixes vary by client, so map them to whatever your setup exposes. If your client has no Open Brain connection, the skill still works — but the failure log has to live somewhere durable, or the compounding value described in Step 7 never materializes.

The bundled [`references/`](./references/) directory is the shared substance. Keep it with the skill no matter which client loads it, and do not rely on reference-to-reference chains: `SKILL.md` is the index.

## Credits

The framework and several of the concrete numbers here — the 83.9% response quality against 32.3% faithfulness case, the six verdict-to-routing actions, the four-signal confidence gate, and the five starter evals — come from the "Eval Engineering" write-up by [@Argona0x](https://x.com/Argona0x). Figures are reported as published; verify anything load-bearing against your own runs before acting on it.
