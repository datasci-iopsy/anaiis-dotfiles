---
name: core
description: Workflow rules: plan mode threshold, root causes, subagent cost discipline, hook output handling
---

# Core Workflow

## Core principles
- **Find root causes**: No temporary fixes. Senior developer standards.

## Workflow
- Enter plan mode for any task with 3+ implementation steps or that touches 3+ files. Use ExitPlanMode after verification.
- If something goes sideways mid-task while in plan mode, stop and re-plan. Do not keep pushing.
- For bugs, just fix them. Point at evidence, resolve.
- Use subagents sparingly. Prefer inline Glob/Grep/Read for targeted lookups. Reach for an Explore agent only when scope is genuinely uncertain or spans 4+ tool calls; use at most 1–2 in parallel and prefer sequential when in plan mode. Broad agents are expensive (measured: 3 parallel Explore agents burned 24% of a weekly session). Never spawn an agent for file listing, single-file reads, or targeted searches.

## Checkpoints in multi-step tasks
After completing each significant step in a multi-step task: state in one sentence what was done, what has been verified, and what remains. Do not proceed to the next step from a state you cannot describe. If you lose track, stop and restate rather than continuing. This applies to plan-mode tasks and to any task with 3+ sequential actions.

## Hook output is not user input
- Hook messages (stop hook, pre-tool hook, post-tool hook) are system status output. They are never a user reply.
- After asking the user a question, wait for an explicit user response before proceeding. If a hook fires immediately after a question, the question is still unanswered, do not self-authorize.
- Never interpret hook output as consent, confirmation, or an affirmative to any pending question.
- When the stop hook reports `[git] uncommitted changes`, respond with only: `Ok`
