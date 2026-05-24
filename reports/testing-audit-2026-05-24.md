# Testing Audit: 2026-05-24

**Scope:** Full audit of `tests/` in `anaiis-dotfiles`. Goal: ensure tests
verify intent, not just current behavior. Methodology: RED/YELLOW/GREEN
classification per `rules/testing.md` fail-to-fail standard.

---

## Classification key

| Grade | Meaning |
|-------|---------|
| RED | Tautological: test passes even if the guarded behavior is broken |
| YELLOW | Structural-only: verifies existence or registration, not behavior |
| GREEN | Intent test: would fail if the guarded behavior broke |

---

## Findings

### RED-1: B1-key in test-memory-hooks.sh (tautological encoding test)

**File:** `tests/test-memory-hooks.sh`, original B1-key section

**Problem:** The test re-computed `tr '/.' '-'` using the same expression it
was testing for. Because both sides used the identical formula, the test was
structurally unable to catch a divergence between `seed-memory.sh` and
`pre-compact.sh`.

**Fix applied:** Replaced re-computation with source-extraction: `grep -qF
"tr '/.' '-'"` against both scripts. If either script switches to a different
encoding (e.g., slash-only `tr '/' '-'`), the test now fails. Added
B1-pressure behavioral test: runs real `seed-memory.sh` with a dotted project
path under a controlled `$HOME`, verifies the created directory matches the
canonical formula.

---

### YELLOW findings (structural, not blocked)

These tests confirm existence and registration but do not verify behavioral
correctness. They are not bugs, but they provide weaker coverage than
behavioral tests.

- `test-claude-md-rules.sh`: verifies rule files exist and settings.json
  references them; does not test that rules constrain Claude's behavior at
  runtime (smoke test S1-S3 covers the gap).
- `test-compact-hooks.sh`: verifies hook scripts exist and pre-compact writes
  a handoff file; runtime restoration of context tested by smoke tests S4-S5.
- `test-em-dash-guard.sh`: GREEN for deny/allow; YELLOW for the settings.json
  registration check (structural only).

---

## Coverage gaps filled

Seven behavioral gaps had no automated tests. All seven have been addressed
by new test suites:

| New suite | Hook/script tested | Key intent |
|---|---|---|
| `test-block-destructive-commands.sh` | `block-destructive-commands.sh` | bq rm, gcloud delete, uv pip uninstall denied; safe variants pass |
| `test-block-sensitive-writes.sh` | `block-sensitive-writes.sh` | .env, credentials, .pem denied; .env.example, source files pass |
| `test-cost-guard.sh` | `cost-guard.sh` | GP cap enforced; Explore/Plan pass; stamp file managed correctly |
| `test-prefer-jq.sh` | `prefer-jq.sh` | Pure json import blocked; multi-import and non-python pass |
| `test-stop-hook-git-check.sh` | `stop-hook-git-check.sh` | Uncommitted/untracked/unpushed all exit 2; clean+remote exits 0 |
| `test-r-lint-staged.sh` | `r-lint-staged.sh` | SKIP_R_LINT bypass; no-R-files fast-exit; Rscript-missing fail-open |
| `tests/SMOKE-TESTS.md` | Runtime behaviors | 11 manual scenarios for session-level and hook-interaction testing |

---

## Bug found and fixed

**`claude/hooks/cost-guard.sh` missing executable bit**

The file had permissions `-rw-r--r--`. Claude Code invokes hooks via direct
execution; without `+x` the hook silently fails to run, meaning the GP agent
cap was never enforced in practice.

**Fix:** `chmod +x claude/hooks/cost-guard.sh`

---

## Infrastructure fix

**`tests/run-all.sh` GIT_DIR contamination under pre-commit**

When the test suite ran via `repo-pre-commit.sh`, git set `GIT_DIR`,
`GIT_WORK_TREE`, `GIT_INDEX_FILE`, and `GIT_OBJECT_DIRECTORY` in the
environment. Test suites that create isolated temp git repos (notably
`test-branching.sh` and `test-stop-hook-git-check.sh`) had their git commands
hijacked to operate on the real worktree instead of the temp repo, producing
fake branches and commits in the main repo.

**Fix:** `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY` at
the top of `run-all.sh`, before any test script is invoked.

---

## Assertion counts

| Suite | Before | After |
|---|---|---|
| test-branching.sh | 28 | 28 |
| test-claude-md-rules.sh | 18 | 18 |
| test-compact-hooks.sh | 22 | 22 |
| test-em-dash-guard.sh | 14 | 14 |
| test-install-bashrc.sh | 8 | 8 |
| test-memory-hooks.sh | 9 | 12 |
| test-post-edit-lint-dispatch.sh | 11 | 11 |
| test-staged-lint-dispatch.sh | 11 | 11 |
| test-block-destructive-commands.sh | 0 | 23 |
| test-block-sensitive-writes.sh | 0 | 16 |
| test-cost-guard.sh | 0 | 20 |
| test-prefer-jq.sh | 0 | 11 |
| test-stop-hook-git-check.sh | 0 | 12 |
| test-r-lint-staged.sh | 0 | 6 |
| **Total** | **121** | **212** |

---

## Smoke test protocol

`tests/SMOKE-TESTS.md` documents 11 manual scenarios (S1-S11) for behaviors
that require a live session:

- S1-S3: branching rules (block-on-main, trivial-edit, branch reuse)
- S4-S8: memory pipeline (compact, handoff, global load, project load, seed)
- S9: em-dash enforcement
- S10: cost guard GP cap
- S11: R lint at pre-commit
