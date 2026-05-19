---
name: git
description: Git workflow guardrails, autonomous commits at logical-unit completion, push is user-initiated, branch verification, staging by name, no force-push, no --no-verify
---

# Git Workflow

## Before any push or commit
- Always run `git branch --show-current` before suggesting a push command. Never assume the branch. Surface the actual branch name in the suggestion.
- Always run `git status --short` before staging. Know what is changed before touching anything.
- Verify branch merge state with `git branch --merged main` or `git log --oneline -5` before reporting it. Never infer from session context.

## Commit autonomy and push discipline
- Commit autonomously at the end of each logical work unit. Do not surface the commit or wait for instruction -- just do it.
- Push is always user-initiated. Never push without explicit instruction, regardless of how many commits are pending.
- Stop hook messages about uncommitted or unpushed changes are status reports. Respond to uncommitted-changes hooks by committing; never push in response to unpushed-commits hooks.
- Never force-push. Never skip hooks (--no-verify).
- Never amend unless explicitly asked.

## Staging and commits
- Stage files by name, not `git add -A` or `git add .`.
- Always create new commits. One logical concern per commit.
- Commit messages: imperative mood, concise, no trailing period.

## Branches and PRs
- **Only** the user creates and owns feature branches (`<user-branch>`) that follow this convention (never create them):
  - `<type>/<linear-id>-<short-title>` (e.g., `feat/ana-758-engagement-survey`, `hotfix/dsio-33-auth-fix`)
  - `<type>/<short-title>` (e.g., `feat/engagement-survey`, `hotfix/auth-fix`)
- Claude always checks and branches from the user's feature branch (i.e., `<user-branch>/`). If no feature branch is detected, stop and notify the user. Claude branches always should follow the convention: 
  - `claude/<topic>` (e.g., `claude/ana-758-engagement-survey`)
- CodeRabbit triage is driven by `/anaiis-coderabbit` (the skill at `claude/skills/anaiis-coderabbit/SKILL.md`). Always run it from a `coderabbit/<topic>` or `claude/<topic>` branch; never from `main`. The skill enforces this as a hard stop in Phase 1.
- For trivial edits (single file, ≤ 5 lines, no new symbols, no config/hook/test changes) while already on the user's feature branch, commit there directly. For all other edits, create a `claude/<topic>` sub-branch. See `rules/branching.md` for the full decision tree, branch-reuse algorithm, and worktree guidance.
- Never push directly to main without explicit instruction.
- Never include session links (`https://claude.ai/code/session_*`) in PR titles, bodies, or descriptions. Sessions are deleted frequently and the links rot.
- When a plan is accepted (ExitPlanMode), branch before the first non-plan edit. Plan files at `~/.claude/plans/` may be written from `main` (the `block-edit-on-main` hook exempts that path), but implementation must run on a `claude/<topic>` branch. If currently on `main`, the first action after plan acceptance is `git checkout -b claude/<topic>`.

## Worktree and branch hygiene

Never assume a worktree path or branch name from session context. Always verify from live git state before giving any merge or checkout instructions.

**Before referencing any worktree:**
- Run `git worktree list` to confirm the path and branch name. EnterWorktree may rename the branch (e.g., `worktree-<name>` becomes `claude/<name>`); never guess the final name.
- If the worktree path is gone, it was cleaned up. Check `git branch --list 'claude/*'` to find the surviving branch.

**Before suggesting a merge:**
- Run `git log --oneline -10` and `git branch --merged main` to determine if the commit is already on `main`. Do not infer from session context alone.
- If the log shows the target commit is already on `main`, say so and skip the merge step entirely.

**Navigation in worktrees:**
- `git checkout main` fails inside a worktree because `main` is checked out in the primary worktree. To return to the primary worktree, the user must `cd` to the repo root or use ExitWorktree. Never suggest `git checkout main` while inside a worktree.
- After ExitWorktree, run `git branch --show-current` to confirm the active branch before giving any follow-on instructions.

## Identity
- Git author identity is enforced via `GIT_AUTHOR_NAME`/`GIT_COMMITTER_NAME` in the harness `env` block (`~/.claude/settings.json`). The `attribution.commit` setting controls only `Co-Authored-By` trailers, not the author name.
