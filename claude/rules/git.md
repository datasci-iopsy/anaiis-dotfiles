---
name: git
description: Branch naming and decision rules, commit discipline, staging by name, push is user-initiated, PR conventions, worktrees for parallel work only
---

# Git Workflow

## Before any push or commit
- Run `git branch --show-current` before suggesting a push command. Never assume the branch; surface the actual name.
- Run `git status --short` before staging.
- Verify branch merge state with `git branch --merged main` or `git log --oneline -5` before reporting it. Never infer from session context.

## Branch naming
- Only the user creates and owns feature branches (never create them): `<type>/<linear-id>-<short-title>` or `<type>/<short-title>` (e.g., `feat/ana-758-engagement-survey`, `hotfix/auth-fix`).
- Claude branches follow `claude-<category>/<short-description>`: `<category>` is a standard software engineering type (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`); `<short-description>` is kebab-case, 5 words or fewer (e.g., `claude-refactor/dotfiles-perf-optimization`).

## Branching decision
Binary rules, checked in order:

1. **On `main` or `master`:** create `claude-<category>/<short-description>` with `git checkout -b` before the first edit. The `block-edit-on-main.sh` hook rejects edits on main; branching first is the resolution. Plan files at `~/.claude/plans/` are exempt and may be written from main; implementation is not.
2. **On a user feature branch, trivial edit:** commit directly to that branch. Trivial means ALL five hold:
   1. `git branch --show-current` returns neither `main`, `master`, nor a name starting with `claude-`.
   2. Exactly one file changed: `git diff --name-only` lists one path.
   3. Total lines changed (insertions + deletions) is 5 or fewer per `git diff --shortstat`.
   4. No new file created and no new named symbol (function, class, method, import, or dependency) introduced.
   5. The changed file is not under `tests/`, `claude/hooks/`, or `claude/skills/`, and does not end in `.json`, `.yaml`, `.toml`, or `.envrc`.
3. **Any other edit:** create a `claude-<category>/<topic>` branch from the current user feature branch.

## Branch reuse
Before creating any new `claude-*` branch, run `git branch --list 'claude-*'`. If an unmerged branch whose name contains the topic slug exists, ask: "Continue on `<existing>`? (y/n)." Never silently create a duplicate of an unmerged branch.

## Staging and commits
- Stage files by name, never `git add -A` or `git add .`.
- One logical concern per commit. Messages: imperative mood, concise, no trailing period.
- Commit autonomously at the end of each logical work unit; do not surface the commit or wait for instruction.
- Never amend unless explicitly asked. Never force-push. Never skip hooks (`--no-verify`).

## Push
- Push is always user-initiated. Never push without explicit instruction, regardless of pending commits.

## Stop hook responses
`stop-hook-git-check.sh` runs on every Stop event and reports git state as one or more `[git] ...` lines; each line carries its own "reply only: Ok" directive inline, so the instruction holds even if this rule file wasn't loaded that session. Any `[git] ...` line, regardless of which condition triggered it (uncommitted changes, untracked files, unpushed commits, deferred CodeRabbit findings), is a status report, never user input:
- Reply with exactly `Ok`. No elaboration, no restating the pending question, no acknowledging the hook by name.
- `[git] uncommitted changes`: commit the pending work per the staging/commit rules above, then reply `Ok`.
- Any other `[git] ...` line: take no autonomous action, just reply `Ok`.
- Never push in response to an unpushed-commits report, no matter the count.
- If a question to the user is still open when this hook fires, it remains open; the hook firing is not the user answering it (see behavioral.md rule 9).

## Pull requests
- Claude never opens a PR on its own initiative: not as a "helpful" follow-on after committing, not auto-chained after another skill, not because the diff looks PR-ready. Opening a PR is visible to others and triggers CI, so it always needs the user's explicit trigger for that specific PR.
- Invoking a skill whose documented job is to open a PR (e.g. `/anaiis-gitpr`) is that explicit trigger. Claude runs the skill's `gh pr create` step as written, without asking a second time within that run; the invocation itself is the authorization. This does not extend past the invocation: it does not license opening additional PRs, reopening a closed one, or opening one from a different, unrelated task.
- Before drafting a PR description, review the structure of the repo's recent merged PRs (`gh pr list --state merged --limit 5`).
- Never include session links (`https://claude.ai/code/session_*`) in PR titles, bodies, or descriptions.
- CodeRabbit triage runs via `/anaiis-coderabbit` from a `claude-*` branch, never from `main`.

## Worktrees (parallel work only)
- Create a worktree only when the user explicitly asks for one ("worktree", "in parallel", "while I keep working on <branch>"). The default for all other work is a branch in place.
- When a worktree is in use: verify its path and branch with `git worktree list` before referencing either; `git checkout main` fails inside a worktree (return via `cd` to the repo root or ExitWorktree); after leaving, confirm the active branch with `git branch --show-current`.

## Branch cleanup
- The `list-merged-claude-branches.sh` hook emits a daily advisory of merged Claude branches with the delete command. Never auto-delete; the user runs the command. Never delete an unmerged branch.

## Identity
- Git author identity is set via `GIT_AUTHOR_NAME`/`GIT_COMMITTER_NAME` in the `env` block of `claude/settings.json`. The `attribution.commit` setting controls only `Co-Authored-By` trailers, not the author name.
