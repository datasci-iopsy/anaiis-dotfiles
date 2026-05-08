---
name: anaiis-gitrebase
description: "Explicit /anaiis-gitrebase, rebase commits into logical groups before PR review"
trigger: /anaiis-gitrebase
---

# Git Rebase (Branch Reconstruction)

Reorganize commits on a feature branch into clean, logically grouped commits for PR review. Uses branch reconstruction instead of `git rebase -i` -- avoids the interactive editor entirely. Claude never force-pushes; the final step hands the user the exact command to run.

## Scope

```
$ARGUMENTS: [branch] [base] [--dry-run]
```

- `branch`: feature branch to rebase (default: current branch)
- `base`: base ref to rebase onto (default: `main`)
- `--dry-run`: run phases 1 and 2 only; output proposed grouping without executing

Examples:
- `/anaiis-gitrebase`
- `/anaiis-gitrebase feature/my-branch main`
- `/anaiis-gitrebase --dry-run`

## Tool usage

- `Bash(git:*)` for all git operations (pre-approved, no permission overhead)
- `Grep`/`Glob` only when file purpose is ambiguous from its path alone
- Never use `Read` to examine file contents for grouping decisions; `--stat` and `--name-only` output is sufficient

**Working directory:** All git commands must start with `git` to match the pre-approved `Bash(git:*)` pattern. If the current shell cwd is not the repo root, use `git -C <absolute-repo-root> <subcommand>` -- never `cd <path> && git <subcommand>`. Determine the repo root once with `git rev-parse --show-toplevel` and use it as the `-C` argument throughout the session.

## Phase 1: Preflight (read-only)

Run as two separate Bash calls. The first resolves the fork SHA; the second uses it as a literal to avoid subshell substitutions that crash the permission parser.

**Call 1, resolve fork point:**
```bash
git status --porcelain && \
git branch --show-current && \
git merge-base <base> HEAD
```

**Call 2, inspect range (substitute the literal SHA returned above for `<fork>`):**
```bash
git log --oneline <fork>..HEAD && \
git log --oneline --merges <fork>..HEAD
```

**Hard stops -- do not proceed if:**
- Working tree is dirty (`git status --porcelain` returns output) -- tell user to stash or commit first
- Merge commits exist in range (last command returns output) -- refuse; merge commits require manual handling
- Detached HEAD -- require a named branch
- No commits in range -- nothing to rebase

## Phase 2: Analysis (read-only)

```bash
git diff --stat <fork>..HEAD && \
git diff --name-only -M <fork>..HEAD && \
git log --oneline --name-only <fork>..HEAD
```

Use `-M` (rename detection) in `--name-only` so renames are grouped correctly rather than appearing as delete + add.

**Grouping heuristics:**
1. Source files in the same module or package group together
2. Test files group with the source files they test
3. Config, tooling, and CI changes (Makefile, pyproject.toml, .github/, linting configs, CodeRabbit config) form their own commit
4. Documentation changes (README, CLAUDE.md) form their own commit unless tightly coupled to a specific feature
5. A file appearing in multiple original commits: use its final state, placed in the logical group matching its purpose
6. Binary files and submodules: flag explicitly and ask the user which group they belong to

**Output format:**

```
Proposed rebase plan (N files, M logical commits):

Commit 1: "feat(scope): description"
  Files:
  - path/to/file1.py
  - path/to/test_file1.py

Commit 2: "chore: description"
  Files:
  - pyproject.toml
  - Makefile
```

If `--dry-run`: output the plan and stop.

---

**GATE 1:** Present the plan and ask the user to confirm, modify, or reject the grouping before any destructive work begins.

---

## Phase 3: Execute (destructive)

**First: capture state and create the safety bookmark.**

Run each command separately (not chained with variable assignments) so each starts with `git`:

```bash
git rev-parse HEAD
git branch --show-current
git tag safety/pre-rebase-<branch> <sha>
```

Use the literal SHA and branch name returned by the above commands in all subsequent calls.

Tell the user:

> Safety bookmark created: `safety/pre-rebase-<branch>` at `<sha>`.
> To revert at any time: `git checkout <branch> && git reset --hard safety/pre-rebase-<branch>`

**Then: build the temp branch.**

```bash
git checkout -b tmp/rebase-${BRANCH} <fork>
```

**For each commit group (in order):**

```bash
git checkout <literal-sha> -- <file1> <file2> ...
git commit -m "<message>"
```

**IMPORTANT -- command formatting:** Always substitute the SHA as a literal hex string directly in the command (e.g., `git checkout abc1234 -- file.py`). Never use shell variable assignments like `FINAL=<sha> && git checkout ${FINAL} --`. Commands must start with `git` to match the pre-approved `Bash(git:*)` allow pattern. If the shell cwd is not the repo root, prefix every command with `git -C <absolute-repo-root>` (e.g., `git -C /path/to/repo checkout abc1234 -- file.py`) -- never use `cd /path && git`. The one exception is `ALLOW_LOCK_COMMIT=1 git commit -m "..."`, which is pre-approved and may be used when the lock file hook would otherwise block a commit.

**File deletions:** if a file existed at the fork point but was deleted by HEAD, use `git rm <file>` in the appropriate group rather than `git checkout`.

**On pre-commit hook failure:** pause immediately. Report which hook tripped and the full output. Ask the user how to proceed:
1. Fix the issue (e.g., run `poetry lock`, fix lint errors) then retry
2. Skip the hook for this commit with `--no-verify` (requires explicit user approval; overrides the CLAUDE.md "never skip hooks" rule for this case only)
3. Abort and revert to the safety tag

## Phase 4: Verify

```bash
git diff <literal-sha> tmp/rebase-<branch>
```

- **Empty diff:** "Tree equality verified. New history produces identical file contents."
- **Non-empty diff:** hard stop. Show the diff. Do NOT proceed. Offer to abort using literal branch/sha values (no shell variable expansions).

---

**GATE 2:** User confirms verification passed and approves the branch swap.

---

## Phase 5: Swap

Use literal branch names (no shell variable expansions):

```bash
git checkout <branch>
git reset --hard tmp/rebase-<branch>
git branch -d tmp/rebase-<branch>
```

Output the final commit log:

```bash
git log <base>..HEAD --oneline
```

## Phase 6: Hand off (Claude does NOT push)

Present the result and the commands for the user to run:

```
Rebase complete. <N> clean commits:

  <sha> <commit 1 message>
  <sha> <commit 2 message>

To publish the rebased history, run:

  git push --force-with-lease origin <branch>

The safety tag `safety/pre-rebase-<branch>` remains. To revert after pushing:

  git reset --hard safety/pre-rebase-<branch>
  git push --force-with-lease origin <branch>

Delete the safety tag when you are satisfied:

  git tag -d safety/pre-rebase-<branch>
```

Claude does not execute the push. This is a human-only action.

## Failure modes and recovery

| Failure | Recovery |
|---|---|
| Dirty working tree | Stash (`git stash`) or commit, then re-run |
| Merge commits in range | Refuse; suggest `git rebase --onto` manually |
| Hook failure during commit | Pause, ask user: fix / skip (with approval) / abort |
| Tree verification fails | `git checkout <branch> && git reset --hard safety/pre-rebase-<branch> && git branch -D tmp/rebase-<branch>` |
| Process interrupted mid-execute | Same revert command as above |
| Wrong files in a group | Revert to safety tag, re-run with corrected grouping |

## Hard limits

- Never execute `git push --force`, `git push --force-with-lease`, or any force-push variant. Human-only action.
- Never proceed past Phase 4 if the tree diff is non-empty.
- Never start without a clean working tree.
- Never operate on a range that includes merge commits.
- Never delete the safety tag -- the user deletes it when satisfied.
- Never use `git rebase -i`.
- Maximum 10 logical commit groups. If more are needed, suggest splitting the PR.

## Integration with other skills

- `anaiis-changelog`: after rebase, run to generate a PR description from the clean commit history.
- `anaiis-preflight`: not needed; this skill does its own git-state preflight in Phase 1.
