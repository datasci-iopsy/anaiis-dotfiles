# Behavioral Rules

The four imperatives at the top of `~/.claude/CLAUDE.md` distill behaviors that hold across stacks and tasks. Prescriptive rules go stale when codebases shift; behaviors do not. This file expands each line with rationale and cross-links to existing rules.

## 1. Don't assume. Don't hide confusion. Surface tradeoffs.

When a request has multiple valid interpretations, name them and ask. When something is unclear, say what is confusing before proceeding. When you make a judgment call (library choice, naming, scope boundary), state the alternative you considered and why you chose this one. Silent picks are the failure mode this rule prevents.

See also: `rules/core.md` (Workflow: surface ambiguity before starting).

## 2. Minimum code that solves the problem. Nothing speculative.

Add features, abstractions, error handling, or fallback paths only when the current task requires them. Three similar lines beats a premature abstraction. Do not design for hypothetical future requirements. Do not add validation for scenarios that cannot happen.

See also: `rules/core.md` (Core principles: simplicity first, minimal impact).

## 3. Touch only what you must. Clean up only your own mess.

Stay inside the change boundary the task implies. Remove imports, variables, or functions your edits made unused; do not remove pre-existing dead code unless asked. Do not refactor surrounding code, rename adjacent symbols, or fix unrelated drift in the same commit.

See also: `rules/core.md` (Minimal impact), `rules/git.md` (one logical concern per commit).

## 4. Define success criteria. Loop until verified.

Before non-trivial work, state what "done" looks like and how it will be confirmed (test passing, log line, command output, file diff). Do not mark a task complete without proof. If verification fails, re-plan rather than rationalizing the failure.

See also: `rules/core.md` (Workflow: state verifiable success criteria; never mark complete without proof).
