# Branching Rules

Supplements `rules/git.md`. These rules govern when to create a sub-branch, when to commit directly, when to use a worktree, and how to reuse existing branches.

## Trivial edits on a user feature branch

When **all** of the following hold, commit directly to the user's feature branch without creating a `claude/<topic>` sub-branch:

- Currently on a `<type>/<topic>` user feature branch (not `main`, not `master`, not `claude/*`).
- Single file modified.
- Net diff ≤ 5 lines.
- No new function, class, import, or dependency introduced.
- No change touches tests, hooks, or config schema.

If any condition fails, create a `claude/<topic>` sub-branch from the user's feature branch before editing.

## Non-trivial edits from main (worktree preferred)

When on `main` or `master` and the work is non-trivial:

1. **Prefer a worktree** over an in-place branch checkout. The main worktree stays on `main` so the user can continue working there without interruption.
   - Via harness: use the `EnterWorktree` tool (auto-managed path under `.claude/worktrees/`).
   - Manual fallback: `git worktree add ../<repo>.worktrees/<topic> -b claude/<topic>`
2. The `block-edit-on-main.sh` hook will fire before any edit attempt on main; treat its output as the cue to create a worktree or branch before proceeding.

For genuinely trivial edits from main (rare; the trivial criteria above apply), still create a `claude/<topic>` branch. Do not commit directly to main.

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
