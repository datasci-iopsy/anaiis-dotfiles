---
name: git
description: Typed claude branches, trivial-edit criteria, Conventional Commits rubric (types, subject grammar, footers, breaking changes, reverts, opt-in lint), PR titles, staging by name, user-initiated push, rebase ours/theirs, criteria for a worktree or a branch in place
---

# Git Workflow

## Before any push or commit
- Run `git branch --show-current` before suggesting a push command. Never assume the branch; surface the actual name.
- Run `git status --short` before staging.
- Verify branch merge state with `git branch --merged main` or `git log --oneline -5` before reporting it. Never infer from session context.

## Branch naming
- Only the user creates and owns feature branches (never create them): `<type>/<ticket-id>-<short-title>` or `<type>/<short-title>` (e.g., `feat/ana-758-engagement-survey`, `hotfix/auth-fix`).
- Claude branches: `claude-<type>/<ticket-id>-<short-kebab-description>`. `<type>` is mandatory, one of the eight below. `<ticket-id>` is the tracker key lowercased (`dsio-86`), from the parent branch name, else the user's message, else ask once; with no ticket drop the segment, never a placeholder. `<short-kebab-description>`: lowercase, hyphens, 5 words or fewer. Examples: `claude-fix/dsio-86-scrub-flags`, `claude-docs/git-conventions`.

| Type | Use for |
|---|---|
| `feat` | New capability or user-visible change |
| `fix` | Correct wrong behavior |
| `refactor` | Restructure, no behavior change |
| `chore` | Deps, tooling, CI, config, maintenance |
| `docs` | Docs only |
| `test` | Tests only |
| `hotfix` | Urgent production fix |
| `wip` | Investigation or prototype, not merge-ready; branches only |

## Branching decision
Binary rules, checked in order:

1. **On `main` or `master`:** create `claude-<type>/<ticket>-<desc>` with `git checkout -b` before the first edit. The `block-edit-on-main.sh` hook rejects edits on main; branching first is the resolution. Plan files at `~/.claude/plans/` are exempt and may be written from main; implementation is not.
2. **On a user feature branch, trivial edit:** commit directly to that branch. Trivial means ALL five hold:
   1. `git branch --show-current` returns neither `main`, `master`, nor a name starting with `claude-`.
   2. Exactly one file changed: `git diff --name-only` lists one path.
   3. Total lines changed (insertions + deletions) is 5 or fewer per `git diff --shortstat`.
   4. No new file created and no new named symbol (function, class, method, import, or dependency) introduced.
   5. The changed file is not under `tests/`, `claude/hooks/`, or `claude/skills/`, and does not end in `.json`, `.yaml`, `.toml`, or `.envrc`.
3. **Any other edit:** create a `claude-<type>/<ticket>-<desc>` branch from the current user feature branch, inheriting `<ticket>` from that branch name when present.

Before applying any branching rule, check the criteria in "Worktree or branch in place". A worktree makes its own branch with `git worktree add -b`.

## Branch reuse
Before creating any new `claude-*` branch, run `git branch --list 'claude-*'`. If an unmerged branch whose name contains the topic slug exists, ask: "Continue on `<existing>`? (y/n)." Never silently create a duplicate of an unmerged branch.

## Staging and commits
- Stage files by name. Never use `git add -A` or `git add .`.
- Make one logical change per commit. Commit at the end of each work unit. Do not surface it and do not wait for an instruction.
- Never amend unless the user asks. Never force-push. Never skip hooks (`--no-verify`).
- Rebase groups follow the same subject rules as any commit.
- Follow the commit rubric below.

## Commit rubric

The rubric is Conventional Commits 1.0.0 with house rules added. The script `claude/scripts/commit-msg-lint.sh` checks the rules that a machine can check. A rule that the script does not check is marked "not enforced".

### Commit types

| Type | SemVer effect | Use for |
|---|---|---|
| `feat` | minor | New capability or user-visible change |
| `fix` | patch | Correct wrong behavior |
| `perf` | patch | Improve speed or resource use, no other behavior change |
| `build` | none | Build system, package manager, dependencies |
| `chore` | none | Tooling, config, maintenance |
| `ci` | none | CI configuration |
| `docs` | none | Docs only |
| `style` | none | Formatting only, no logic change |
| `refactor` | none | Restructure, no behavior change |
| `test` | none | Tests only |
| `revert` | none | Undo an earlier commit |

A `!` after the type, or a `BREAKING CHANGE` footer, makes the change major for SemVer, whatever the type.

### Branch-only prefixes

| Prefix | Use for |
|---|---|
| `hotfix` | Urgent production fix. A hotfix commit uses `fix`. |
| `wip` | Investigation or prototype, not merge-ready. A `wip` branch still commits with a real type. |

Never use a branch-only prefix as a commit type.

### Subject

Write the subject as `<type>[(scope)][!]: <description>`.

- The type and the scope are lowercase.
- The scope names one component, tool, or directory. It matches `[a-z0-9][a-z0-9._/-]*`. Examples: `bash-guard`, `dbt`, `deps`.
- The `!` sits immediately before the colon.
- One space and a non-space character follow the colon.
- Start the description with a lowercase letter. Code identifiers and proper nouns are the exceptions. Not enforced.
- Write the description in the imperative. It completes the sentence "If accepted, this commit will ...".
- Keep the first line to 72 characters or fewer. Do not end it with a period.
- Do not write `WIP` in the subject.
- State the intent. Never write `fix`, `changes`, `address review comments`, or a subject that only restates the diff.

### Body and footers

- Put a blank line between the subject and the body.
- Write a body only when the diff cannot explain why. State the problem and the reason in 1 to 3 sentences.
- Wrap body lines at 72 characters. Not enforced.
- Put footers in the last paragraph, after a blank line. A footer has the form `Token: value` or `Token #value`.
- Write a footer token as `Capitalized-With-Hyphens`, for example `Refs` or `Reviewed-by`. The one exception is `BREAKING CHANGE`, in uppercase.
- Do not start a line in the last paragraph with a label of two or three words and a colon, for example `Root cause: ...`. The lint reads it as a footer with a bad token. Write `Root-cause: ...` or move the line up.
- Put a ticket or decision reference in a `Refs: <ID>` footer. Never put it in the subject.
- Add `Closes: <ID>` only when the PR must close the ticket.
- Add no `Claude-Session:` trailer and no session link (`https://claude.ai/code/session_*`) to a commit message.

### Breaking changes

- Add `!` before the colon for every breaking change.
- When one line cannot say what breaks, add the footer `BREAKING CHANGE: <what breaks and how to migrate>`. The token `BREAKING-CHANGE` means the same.
- A `BREAKING CHANGE` footer needs the `!` in the subject. The lint enforces this.

### Reverts

- Write the subject as `revert: <original subject>`. Shorten the original subject if the line would pass 72 characters.
- Write the body as `This reverts commit <full SHA>.`

### Exemptions

Git writes some subjects itself. The lint skips them: a subject that starts with `Merge `, the default `Revert "<subject>"`, and the autosquash prefixes `fixup! ` and `squash! `. The lint also ignores lines that start with `#`. Do not write an exempt subject by hand. Use `revert:` for a revert.

### Pull request titles

A PR title follows the subject grammar and ends with the ticket in brackets (see Pull requests). The title carries the `!` when the PR holds a breaking change.

### Lint

- The validator is `claude/scripts/commit-msg-lint.sh`. To check a draft, run `bash ~/.claude/scripts/commit-msg-lint.sh <message-file>`. To print the allowed types, add the `--types` flag instead of a file.
- The `commit-msg` hook runs the validator only in a repo whose working tree has a `.conventional-commits` file at its root. This repo has that file. Other repos accept any message.
- If the lint rejects a message, fix the message.
- `SKIP_COMMIT_LINT=1 git commit` bypasses the lint. Only the user uses it. Claude never uses it.

### Subject examples

```
fix(audit-log): normalize tracker timestamps
feat(attrition): add manager-tenure feature
refactor(dbt): extract employee-status macro
docs(runbook): document survey backfill process
test(ingestion): cover duplicate-event handling
build(deps): upgrade dbt-utils
feat(api)!: drop the v1 endpoints
revert: feat(attrition): add manager-tenure feature
```

### Full message example

```
feat(api)!: drop the v1 endpoints

Clients on v1 lose access when the endpoints go away. The v2 endpoints
return the same data.

BREAKING CHANGE: remove /v1/*. Call /v2/* with the same parameters.
Refs: D-12
```

## Push
- Push is always user-initiated. Never push without explicit instruction, regardless of pending commits.

## Rebase conflict resolution (ours/theirs)
- `git rebase` inverts the merge convention: during a rebase, `ours` is the branch being rebased onto (the base, plus already-replayed commits), and `theirs` is the commit currently being replayed. This is the opposite of `git merge`, where `ours` is the current checked-out branch. Using `--ours`/`--theirs` on the merge-conflict assumption during a rebase silently keeps the wrong side.
- **Why:** during a manual rebase, a docs-regeneration commit's conflict was resolved with `--ours`, which discarded that commit's entire own diff. The commit became empty and `git rebase` silently dropped it, no error, no warning. Caught only by counting commits before and after.
- **How to apply:** before running `git checkout --ours <file>` or `--theirs <file>` mid-rebase, confirm which side actually holds the content worth keeping (read the conflict markers, or the commit's own diff) rather than defaulting to merge-conflict habits. After any rebase, verify the commit count matches expectations (`git log --oneline <base>..<branch> | wc -l`) rather than assuming nothing was lost.

## Stop hook responses
`stop-hook-git-check.sh` runs on every Stop event and reports git state as one or more `[git] ...` lines; each line carries its own "reply only: Ok" directive inline, so the instruction holds even if this rule file wasn't loaded that session. Any `[git] ...` line, regardless of which condition triggered it (uncommitted changes, untracked files, unpushed commits, deferred CodeRabbit findings), is a status report, never user input:
- Reply with exactly `Ok`. No elaboration, no restating the pending question, no acknowledging the hook by name.
- `[git] uncommitted changes`: commit the pending work per the staging/commit rules above, then reply `Ok`.
- Any other `[git] ...` line: take no autonomous action, just reply `Ok`.
- Never push in response to an unpushed-commits report, no matter the count.
- If a question to the user is still open when this hook fires, it remains open; the hook firing is not the user answering it (see behavioral.md rule 6).

## Pull requests
- Claude never opens a PR on its own initiative: not as a "helpful" follow-on after committing, not auto-chained after another skill, not because the diff looks PR-ready. Opening a PR is visible to others and triggers CI, so it always needs the user's explicit trigger for that specific PR.
- Invoking a skill whose documented job is to open a PR (e.g. `/anaiis-git-ops:pr`) is that explicit trigger. Claude runs the skill's `gh pr create` step as written, without asking a second time within that run; the invocation itself is the authorization. This does not extend past the invocation: it does not license opening additional PRs, reopening a closed one, or opening one from a different, unrelated task.
- Title: `<type>(<scope>): <description> [<TICKET-ID>]`, the commit subject rule plus the ticket in brackets, uppercase as tracked; mandatory whenever the branch or work has one, omitted only when none exists. Example: `fix(audit-log): normalize tracker timestamps [PA-217]`.
- Body, in order: Summary (what and why), Ticket (`Closes <ID>` or link), Changes, Validation (what was run). Add Data impact when a model, table, metric, or backfill changes; the PR skill holds the template.
- One ticket or cohesive change per PR.
- Before drafting a PR description, review the structure of the repo's recent merged PRs (`gh pr list --state merged --limit 5`).
- Never include session links (`https://claude.ai/code/session_*`) in PR titles, bodies, or descriptions.
- CodeRabbit triage runs via `/anaiis-coderabbit` from a `claude-*` branch, never from `main`.

## Worktree or branch in place

Use a worktree when any one of these four holds. Check them in order. When you create the worktree, name the criterion that held.

1. **Live config.** The change touches a path that the `~/.claude/` links reach (`claude/hooks/`, `claude/scripts/`, `claude/rules/`, `claude/skills/`, `claude/commands/`, `claude/agents/`, `claude/memory/`, `claude/settings.json`) or the file `bash/shared.bash`. Why: the links point at the main checkout, so an edit in place changes the running harness before the tests pass. A worktree stays inert until it merges.
2. **Foreign changes.** `git status --short` in the main checkout lists a change that is not part of the task. Why: a branch in place carries that change into the commits.
3. **Parallel streams.** Two or more sessions or branches work at the same time. Why: one checkout holds one branch.
4. **The user asks** for a worktree ("worktree", "in parallel", "while I keep working on <branch>").

If none holds, use a branch in place (see "Branching decision"). In the dotfiles repo, criterion 1 holds for nearly all work, so a worktree is the default there.

- Path: the `AGENTS.md` of the project names it. The dotfiles repo uses `tmp/worktrees/<id>`. A project with no such line uses `../<repo>.worktrees/<id>`. `<id>` is the short name of the work.
- Create it with `git -C <main-checkout> worktree add <path> -b claude-<type>/<ticket>-<desc> <base>`. The `-b` flag makes the branch. `<base>` is the current branch, or `main` when the current branch is `main`.
- Gitignored inputs such as `spec/` and `tasks/` exist only in the main checkout. Read and write them there by absolute path.
- An uncommitted foreign change (criterion 2) does not enter the worktree. For a tracked path, save all changes with `git diff HEAD --binary -- <path>`. For an untracked path, copy the file by hand. In the worktree, apply the diff or add the copied file. Commit it on its own. Then tell the user to run `git restore <path>` in the main checkout before `git pull`, because the merge touches the same file.
- Merging, pushing, and removing the worktree stay with the user (see "Push" and "Branch cleanup").
- When a worktree is in use: verify its path and branch with `git worktree list` before referencing either; `git checkout main` fails inside a worktree (return via `cd` to the repo root or ExitWorktree); after leaving, confirm the active branch with `git branch --show-current`.

## Branch cleanup
- The `list-merged-claude-branches.sh` hook emits a daily advisory of merged Claude branches with the delete command. Never auto-delete; the user runs the command. Never delete an unmerged branch.

## Identity
- Git author identity is set via `GIT_AUTHOR_NAME`/`GIT_COMMITTER_NAME` in the `env` block of `claude/settings.json`. The `attribution.commit` setting controls only `Co-Authored-By` trailers, not the author name.
