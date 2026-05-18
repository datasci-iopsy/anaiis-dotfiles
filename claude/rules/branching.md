# Branching Rules

Supplements `rules/git.md`. These rules govern when to create a sub-branch, when to commit directly, when to use a worktree, and how to reuse existing branches.

## Trivial edits on a user feature branch

When **all five** of the following hold, commit directly to the user's feature branch without creating a `claude/<topic>` sub-branch:

1. Currently on a `<type>/<topic>` user feature branch: `git branch --show-current` does not return `main`, `master`, or any name starting with `claude/`.
2. Exactly one file changed: `git diff --name-only` lists one path (covers modified, added, and deleted files).
3. Total lines changed ≤ 5: insertions + deletions combined, as reported by `git diff --shortstat`.
4. No new file created and no new named symbol (function, class, method, import, or dependency) introduced in the changed file.
5. The changed file is not under `tests/`, `claude/hooks/`, or `claude/skills/`, and does not end in `.json`, `.yaml`, `.toml`, or `.envrc`.

Each criterion has a binary answer given the file diff. If any returns "no", create a `claude/<topic>` sub-branch from the user's feature branch before editing.

## Edits from main

When on `main` or `master`, **always use a worktree**. There is no trivial exception from main.

1. Use the `EnterWorktree` tool (auto-managed path under `.claude/worktrees/`). The main worktree stays on `main` so the user can continue working there without interruption.
   - Manual fallback: `git worktree add ../<repo>.worktrees/<topic> -b claude/<topic>`
2. The `block-edit-on-main.sh` hook fires before any edit attempt on main; treat its output as the cue to enter a worktree before proceeding.

Never use `git checkout -b` from main. `EnterWorktree` first, then edit.

## Branch reuse

Before creating any new `claude/<topic>` branch:

1. Extract a topic slug from the current request (kebab-case, ≤ 5 words).
2. Run: `git branch --list 'claude/*'`
3. If a branch whose name contains the topic slug exists **and** is not yet merged to its base, ask: "Continue on `claude/<existing>`? (y/n)." Default to yes if no response after one exchange.
4. If no matching unmerged branch exists, create a new one.

Never silently create a duplicate branch when a matching unmerged one exists.

## Cleanup

Dead `claude/*` branches accumulate over time. The `list-merged-claude-branches.sh` hook emits an advisory at session start when merged branches are detected. Never auto-delete branches. Always present the list and the `git branch -d` command for the user to run manually.

A branch is only deleted when:
- It has been merged to its base branch, AND
- The user explicitly runs the delete command shown in the advisory.

Never delete a `claude/*` branch that has not been merged, regardless of age.

## Priority vs. git.md

These rules extend `rules/git.md` and do not override it. The `claude/<topic>` convention, one-logical-concern-per-commit, and no-force-push rules from `git.md` still apply. When this file and `git.md` appear to conflict, surface the conflict rather than choosing silently.
