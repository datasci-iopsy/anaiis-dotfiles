# Smoke Test Protocol

Manual scenarios that verify runtime behavior automated tests cannot reach.
Each scenario requires a live Claude Code session and real hook execution.

Run these when: hooks are modified, settings.json is changed, or after a new
machine setup. Not part of the automated suite.

---

## S1: block-edit-on-main fires in session

**Precondition:** Checked out on `main` in the primary worktree.

**Steps:**
1. Ask Claude to make any file edit.
2. Observe the PreToolUse hook fires before the edit executes.

**Expected:** Hook output contains `BLOCKED`. Claude creates a
`claude-<category>/<short-description>` branch before proceeding.

**Fail condition:** Edit executes directly on `main` with no hook message.

---

## S2: Trivial-edit on feature branch commits directly

**Precondition:** On a user feature branch (e.g., `feat/my-feature`). One file
changed with <= 5 lines delta, no new symbols.

**Steps:**
1. Ask Claude to make a small fix meeting all five trivial-edit criteria from
   `rules/git.md`.

**Expected:** Claude commits directly to the feature branch without creating a
`claude-*` sub-branch.

**Fail condition:** Claude creates a `claude-<category>/<topic>` branch for a
single trivial line change.

---

## S3: Branch reuse algorithm fires

**Precondition:** An unmerged `claude/<topic>` branch exists.

**Steps:**
1. Ask Claude to work on a task whose slug matches the existing branch name.

**Expected:** Claude asks "Continue on `claude/<existing>`? (y/n)" before
creating a new branch.

**Fail condition:** Claude silently creates a duplicate `claude/<topic>` branch.

---

## S4: Pre-compact hook writes handoff file

**Precondition:** Active session with work in progress.

**Steps:**
1. Run `/compact`.

**Expected:** A timestamped handoff file appears in
`~/.claude/projects/<key>/memory/handoffs/`. Session resumes with context
preserved.

**Fail condition:** No handoff file written; session loses context after
compact.

---

## S5: Post-compact hook restores handoff

**Precondition:** A handoff file exists from a prior compact (S4 completed).

**Steps:**
1. Run `/compact` a second time.

**Expected:** Claude references prior session context in the restored summary.
Rolling cap: only 5 handoff files retained in `handoffs/`.

**Fail condition:** Handoff content not restored; Claude starts fresh with no
prior context.

---

## S6: Global memory loads once per session

**Precondition:** `~/.claude/memory/` is seeded (run `seed-memory.sh`).

**Steps:**
1. Start a new session.
2. Submit any prompt.

**Expected:** The UserPromptSubmit hook loads global memory exactly once. A
marker file `/tmp/claude-session-<sid>.global-loaded` is created. Subsequent
prompts in the same session do not re-load.

**Fail condition:** Memory loads on every prompt, or marker file is absent.

---

## S7: Project memory loads via MEMORY.md

**Precondition:** Working in a project with a seeded project memory tier.

**Steps:**
1. Start a new session in the project directory.
2. Ask about a fact that lives in project memory.

**Expected:** Claude recalls the project-specific fact without being told it
in the current conversation.

**Fail condition:** Claude cannot recall project facts that are in memory files.

---

## S8: seed-memory.sh does not overwrite existing files

**Precondition:** Project memory already seeded (`~/.claude/projects/<key>/memory/`
exists with content).

**Steps:**
1. Edit a memory file to add a custom note.
2. Run `bash ~/.claude/scripts/seed-memory.sh` again.

**Expected:** Existing file is preserved unchanged. Script output shows
"exists (skipped)" for that file.

**Fail condition:** Custom edits are overwritten by the template.

---

## S9: Em-dash hook blocks write

**Precondition:** None.

**Steps:**
1. Ask Claude to write a file containing a U+2014 em dash character.

**Expected:** The `block-em-dash.sh` PreToolUse hook fires with exit 2.
Claude rewrites the output without the em dash and retries.

**Fail condition:** File containing U+2014 is written to disk.

---

## S10: Cost guard blocks GP agent above cap

**Precondition:** `COST_GUARD_GP_LIMIT` is at default (5) or set to a low
number (e.g., 2). Session stamp file pre-seeded or spawns accumulated.

**Steps:**
1. Trigger enough general-purpose agent spawns to exceed the cap.

**Expected:** On spawn N+1 (where N = cap), hook outputs
`[COST GATE BLOCK] General-purpose agent #N+1 exceeds session cap (N).`
and exits 2. Claude surfaces the block to the user.

**Fail condition:** Agent spawns continue past cap with no block.

---

## S11: R lint staged hook runs at pre-commit

**Precondition:** R and lintr are installed. A staged `.R` file with a lint
violation (e.g., `T` used instead of `TRUE`).

**Steps:**
1. Stage the R file.
2. Attempt `git commit`.

**Expected:** Pre-commit hook runs `r-lint-staged.sh`. Commit is blocked with
lintr findings shown. `SKIP_R_LINT=1 git commit` bypasses successfully.

**Fail condition:** Commit goes through with lint violations undetected, or
`SKIP_R_LINT=1` does not bypass the check.

---

## S12: Read deny rules block secret files (fresh session)

**Precondition:** Fresh session (permission rules load at session start).
Create a throwaway fixture first: `mkdir -p /tmp/smoke-sec && echo
"FAKE_API_KEY=not-real" > /tmp/smoke-sec/.env`

**Steps:**
1. Ask Claude to read `/tmp/smoke-sec/.env` with the Read tool.
2. Ask Claude to read `~/.bashrc` with the Read tool.
3. Ask Claude to read `~/anaiis-dotfiles/bash/shared.bash` (the canonical shared shell config in the repo).

**Expected:** Steps 1 and 2 are denied by the permission rules. Step 3
succeeds (the repo copy is the canonical, readable shell content).

**Fail condition:** Either secret read succeeds, or the repo file is blocked.

---

## S13: bash-guard blocks secret paths and env dumps in session

**Precondition:** Fresh session; fixture from S12 exists.

**Steps:**
1. Ask Claude to run `cat /tmp/smoke-sec/.env` in Bash.
2. Ask Claude to run `printenv` in Bash.

**Expected:** Both are blocked by `bash-guard.sh` with a BLOCK message
(exit 2). Claude reports the block instead of working around it.

**Fail condition:** Either command executes, or Claude retries via another
read mechanism without asking.

---

## S14: Write deny rules protect shell config (fresh session)

**Steps:**
1. Ask Claude to append a comment line to `~/.bashrc`.

**Expected:** The Write/Edit is denied by the permission rules.

**Fail condition:** The edit lands in `~/.bashrc`.

---

## S15: Normal workflows unaffected by secrets denial

**Steps:**
1. `gh pr list` (or `gh auth status`), `bq ls`, one `duckdb -json` query on
   a fixture, and one Edit + commit round-trip in a scratch repo.

**Expected:** All succeed without spurious BLOCK messages.

**Fail condition:** Any routine command is blocked by the secrets guard.

---

## S16: Key-workflow verification after secret migration (user terminal)

Run these yourself in a plain terminal after migrating keys per
`rules/environment.md`:

1. Tier 1: `gh auth status` (token from keyring, not env);
   `coderabbit auth status`; `postman whoami`.
2. Tier 2: inside a project whose `.envrc` has
   `dotenv ~/.config/secrets/global.env`:
   `direnv exec . sh -c 'test -n "$QUALTRICS_API_KEY" && echo loaded'`.
3. Tier 2 scoping: outside any project, `printenv QUALTRICS_API_KEY`
   returns nothing.
4. Rotate the key families listed in `tmp/file-history-audit.txt` and
   delete the archives it lists. This file is untracked (gitignored) and
   local to whichever machine it was generated on; it does not sync via git.

**Expected:** 1-2 succeed; 3 prints nothing; 4 completed once.

**Fail condition:** A tier-2 var is visible outside its projects, or any
CLI stops authenticating after the migration.
