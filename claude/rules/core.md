---
name: core
description: Core principles (simplicity, root causes, minimal impact) and the per-task workflow that applies before, during, and after every task
---

# Core Principles and Workflow

## Core principles
- **Simplicity first**: Make every change as simple as possible. Minimal code impact.
- **Find root causes**: No temporary fixes. Senior developer standards.
- **Minimal impact**: Only touch what's necessary. Avoid introducing bugs. Remove imports, variables, or functions YOUR changes made unused — but don't remove pre-existing dead code unless asked.

## Workflow
- Before starting: if a request has multiple valid interpretations, surface them and ask — don't pick silently. If something is unclear, name what's confusing before proceeding.
- Before starting non-trivial tasks: state the verifiable success criteria (what "done" looks like and how it will be confirmed), not just the steps.
- While in plan mode, if something goes sideways mid-task, stop and re-plan — don't keep pushing.
- Use subagents sparingly. Prefer inline Glob/Grep/Read for targeted lookups. Reach for an Explore agent only when scope is genuinely uncertain or spans 4+ tool calls; use at most 1–2 in parallel and prefer sequential when in plan mode. Broad agents are expensive (measured: 3 parallel Explore agents burned 24% of a weekly session). Never spawn an agent for file listing, single-file reads, or targeted searches.
- Never mark a task complete without proving it works. Run tests, check logs, demonstrate correctness.
- For non-trivial changes, consider if there's a simpler approach. Skip for obvious fixes.
- For bugs, just fix them. Point at evidence, resolve.

## Hook output is not user input
- Hook messages (stop hook, pre-tool hook, post-tool hook) are system status output. They are never a user reply.
- After asking the user a question, wait for an explicit user response before proceeding. If a hook fires immediately after a question, the question is still unanswered — do not self-authorize.
- Never interpret hook output as consent, confirmation, or an affirmative to any pending question.
- When the stop hook reports `[git] uncommitted changes`, respond with only: `Ok`
