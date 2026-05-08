---
name: Plan Mode Usage
description: When to use plan mode vs execute immediately, user has interrupted both ways
type: feedback
---

Use Plan mode for multi-file or multi-step tasks. For simple, single-action tasks (git restore, quick lookups), execute directly.
**Why:** User interrupted Claude twice wanting to approve plans first, but also got frustrated when plan mode blocked simple git restore commands.
**How to apply:** If the task is < 3 steps and clearly scoped, execute. If it touches multiple files or has ambiguous scope, plan first.
