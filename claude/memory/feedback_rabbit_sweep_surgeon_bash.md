---
name: rabbit-sweep-surgeon-bash
description: code-surgeon agent (anaiis-review:rabbit-sweep) is gaining Bash access; underlying principle is to bypass a subagent's tool gap rather than stop work
metadata:
  type: feedback
---

`anaiis-review:rabbit-sweep`'s `code-surgeon` subagent (Read, Grep, Glob, Edit only, no Bash) produced an incomplete fix for a CodeRabbit finding that required regenerating a derived file (a mojibake-normalization fix to a codebook generator, verified during a full local-mode run on 2026-07-31). The agent could edit the generator script correctly but could not re-run the pipeline or verify the output byte-for-byte, so it hand-edited the generated artifact and got it half right (handled the trailing `\xa0` but missed the leading `\xc2` half of the mojibake pair). The main-loop agent caught this only because it independently re-derived the file with Bash and diffed the result.

The user is adding Bash access to `code-surgeon`'s tool list when next updating the skill (it already has Edit/write access, so Bash is a natural extension, not a scope expansion). **Before relying on this, verify `code-surgeon`'s current tool list** (agent definition at `review/agents/code-surgeon.md` in the `anaiis-review` plugin, or check the Agent-tool listing's `(Tools: ...)` annotation at session start), this memory describes a gap identified on 2026-07-31; confirm it wasn't already fixed before assuming it still applies.

**Why:** a subagent's tool restriction is not a reason to accept an unverified or partial fix. When the orchestrating agent has broader tool access (Bash, in this case) than the subagent it dispatched, and the subagent's incomplete work can be independently verified or completed with that broader access, do so instead of stopping and handing the gap back to the user as a blocker.

**How to apply:** any time a dispatched subagent (in `rabbit-sweep` or elsewhere) reports uncertainty, a manual workaround, or an inability to verify its own fix because of a missing tool, and the main loop has the missing capability, use it to independently verify or complete the fix before moving on. Flag the gap in the final report, but let it be a footnote, not a stopping point.
