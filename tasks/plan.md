# Memory System Evolution: Implementation Plan

## Constraints (from user, non-negotiable)

1. **No MCPs.** Any augmentation must integrate via CLI tools called from hook scripts. If a candidate tool has no usable CLI surface, Phase C is skipped, not adapted.
2. **Testing is load-bearing.** Every code change requires: a smoke test (does it run without error?), a key assertion test (does it do the right thing?), and at least one pressure test (does it fail correctly under adversarial input?). Tests follow the existing `tests/test-*.sh` pattern with `pass()`/`fail()` helpers and `mktemp -d` isolation.
3. **Current system is not broken.** Phase A is a measurement gate: if injection cost is within budget, Phases C-E are dropped without any changes to hooks.

## Architecture of the existing system (do not break)

| Component | File | Role |
|---|---|---|
| Global tier injector | `claude/hooks/load-global-memory.sh` | Reads `~/.claude/memory/MEMORY.md` + linked files; emits full content as `systemMessage` on first `UserPromptSubmit` |
| Behavioral rules surfacer | `claude/hooks/surface-behavioral-rules.sh` | Extracts H2 imperatives from `behavioral.md`; emits on first prompt; MUST NOT be touched |
| Pre-compact snapshot | `claude/hooks/pre-compact.sh` | Writes `handoffs/handoff_<ts>_<sid8>.md`; rolling cap of 5 |
| Post-compact restore | `claude/hooks/post-compact.sh` | Re-injects most recent handoff after compaction; MUST NOT be touched |
| Project tier seeder | `claude/scripts/seed-memory.sh` | Initializes project memory from templates; encoding bug at line 46 |
| Session cleanup | `claude/scripts/cleanup-sessions.py` | Removes stale JSONL + project dirs; does NOT clean `/tmp/` markers |
| Pipeline verifier | `claude/scripts/memory-doctor.sh` | Checks A-G; must pass after every change |
| Test suite | `tests/` | `test-*.sh` scripts; `run-all.sh` aggregates; all must pass after every change |

## Dependency graph

```
Phase A (measure)
    |
    +-- threshold < 5k tokens --> STOP (system is correctly sized)
    |
    +-- threshold >= 5k tokens --> Phase C0 (CLI viability gate)
                                       |
                                       +-- mem0-cli has no recall CLI --> STOP
                                       |
                                       +-- viable --> Phase C1-C4 (augment)

Phase B (local fixes)
    -- independent of Phase A/C, can run in any order --
    B1: seed-memory.sh encoding fix
    B2: cleanup-sessions.py marker prune
```

---

## Phase A: Measure injection cost

**Goal:** Produce a reproducible, numerical baseline for the tokens injected per session by `load-global-memory.sh` and the project tier. This is the decision gate for all subsequent work.

**Why:** The primary weakness of the current system is wholesale injection. Before adding complexity to solve it, confirm the problem is real. Token cost that is under 5k is not worth solving.

### A1: Write `tests/measure-memory-injection.sh`

**What it does:**
- Invokes `load-global-memory.sh` with a synthetic JSON input (valid `session_id`, no marker file present)
- Captures the emitted `systemMessage` value via `jq -r '.systemMessage'`
- Measures: raw bytes, estimated tokens (chars / 3.5), file count
- Repeats for project tier: sums byte sizes of `MEMORY.md` + all linked topical files for the active project
- Writes a structured report to `reports/memory-cost-baseline.md`
- Cleans up its own `/tmp/` marker after each measurement run

**Test cases (within the script itself):**
1. **Smoke:** hook emits valid JSON with a `systemMessage` field. `jq -e '.systemMessage'` must succeed.
2. **Idempotency assertion:** run hook twice with the same session ID; second run must emit nothing (exit 0, empty stdout). The marker system must hold.
3. **Pressure - missing MEMORY.md:** move `~/.claude/memory/MEMORY.md` aside, run hook, expect exit 0 + empty stdout (silent skip). Restore the file.
4. **Pressure - invalid session_id:** pass a session_id containing `../` path chars; expect exit 0 + empty stdout (guard must fire).
5. **Pressure - missing jq:** PATH override hiding jq binary; expect exit 0 + empty stdout.

**Acceptance criterion:** all 5 test cases pass. The measurement output in `reports/memory-cost-baseline.md` contains: global tier byte count, global tier estimated token count, project tier byte count, project tier estimated token count, total estimated tokens, and a PASS/STOP decision line.

**Key files:**
- New: `tests/measure-memory-injection.sh`
- New: `reports/memory-cost-baseline.md` (written by the script at runtime, not committed)
- Read: `claude/hooks/load-global-memory.sh` (understand payload structure before writing test)

**Decision gate:** if total estimated tokens < 5,000, append `DECISION: within budget, stop here` to the report and do not proceed to Phase C.

---

## Phase B: Local fixes

Both B1 and B2 are independent of Phase A's outcome. They fix documented bugs and gaps. Each requires its own test coverage added to `tests/test-memory-hooks.sh` (new file).

### B1: Fix `seed-memory.sh` encoding divergence

**Bug:** `seed-memory.sh:46` uses `${PROJECT_PATH//\//-}` which replaces only `/`. `pre-compact.sh` and `post-compact.sh` use `tr '/.' '-'` which also replaces `.`. For paths containing a dot (e.g., `/Users/user.name/project`), `seed-memory.sh` creates a project key that the compaction hooks cannot find.

**Fix:** change line 46 from:
```bash
ENCODED="${PROJECT_PATH//\//-}"
```
to:
```bash
ENCODED=$(echo "$PROJECT_PATH" | tr '/.' '-')
```

**Test cases (in `tests/test-memory-hooks.sh`):**
1. **Smoke:** `bash claude/scripts/seed-memory.sh` on a fresh `mktemp -d` tmpdir (no dotfiles, using `--dry-run` if flag is present, or by pointing HOME at tmpdir) exits 0.
2. **Key assertion:** for path `/tmp/test.dotted/repo`, bash substitution produces `--tmp-test.dotted-repo` while `tr '/.' '-'` produces `--tmp-test-dotted-repo`. After the fix, script output must match the `tr` result.
3. **Pressure:** path with multiple dots (`/Users/d.k.green/my.project`) must produce the same key from `seed-memory.sh` and from `pre-compact.sh`'s key derivation. Compute both and assert equality.
4. **Regression:** path with no dots (current machine: `/Users/dkgreen-mmai/anaiis-dotfiles`) must produce the same key as before the fix (replacing `/` with `-` is unchanged). Assert the key is unchanged for this case.

**Acceptance criterion:** all 4 test cases pass. `bash ~/.claude/scripts/memory-doctor.sh` exits 0, all checks A-G pass.

### B2: Add `--prune-markers` to `cleanup-sessions.py`

**Bug:** `/tmp/claude-session-<id>.global-loaded` and `/tmp/claude-session-<id>.behavioral-loaded` files accumulate over time. No script removes them. macOS clears `/tmp/` on reboot so this is low-severity, but orphaned markers suppress memory injection for sessions that no longer exist.

**Fix:** add a `--prune-markers` flag to `cleanup-sessions.py` that:
1. Lists all session IDs from `/tmp/claude-session-*.global-loaded` marker filenames
2. For each, checks whether a corresponding session exists in `~/.claude/projects/` directories (any `*.jsonl` file for that session ID)
3. Removes markers for session IDs with no corresponding session

**Test cases (in `tests/test-memory-hooks.sh`):**
1. **Smoke:** `python3 claude/scripts/cleanup-sessions.py --prune-markers --dry-run` exits 0 with no `/tmp/` markers present.
2. **Key assertion:** create two fake markers (`/tmp/claude-session-FAKEID1.global-loaded` and `.behavioral-loaded`). Run `--prune-markers` (not dry-run). Verify both are removed. Verify no non-marker `/tmp/` files were touched.
3. **Live session guard:** create a marker for a session ID that HAS a `.jsonl` file in `~/.claude/projects/` (use a real recent session ID). Run `--prune-markers`. Verify the marker is NOT removed.
4. **Pressure - no `/tmp/` permission:** restrict write access to the test `/tmp/` marker path, verify the command exits non-zero or reports an error rather than silently failing to delete.

**Acceptance criterion:** all 4 test cases pass. `bash ~/.claude/scripts/memory-doctor.sh` exits 0, all checks A-G pass.

---

## Phase C: CLI viability gate (conditional on Phase A threshold exceeded)

**Skip this entire phase if Phase A finds total injection < 5,000 tokens.**

### C0: Verify `mem0-cli` has a usable recall CLI surface

**What to verify:**
1. `pipx install mem0ai` or `uv tool install mem0ai` completes cleanly
2. `mem0-cli --help` shows a subcommand for search/recall/query
3. `mem0-cli search "test query"` returns JSON output (not an error or interactive prompt)
4. Output JSON contains a list of memory results with text content
5. All of the above works without an `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` in the environment (i.e., with a local-only configuration)

**Test (manual, not automated):** run each command above and document the actual output in `reports/mem0-pilot.md`.

**Decision gate:** if any of items 1-5 fails, append `DECISION: mem0-cli does not have a viable CLI surface for hook integration; Phase C skipped` to `reports/mem0-pilot.md` and stop here.

### C1: Local mem0 configuration

**Applies only if C0 passed.**

**Goal:** configure mem0 to run fully locally (no data egress, no external API calls) using a local embedding model and a local vector store.

**Setup:**
1. Install mem0 in `vendor/mem0-venv/` using `uv venv + uv pip install mem0ai sentence-transformers` (mirrors `graphify` precedent)
2. Create `claude/config/mem0.yaml` with:
   - Vector store: Qdrant (Docker) OR FAISS (no Docker, simpler) - prefer FAISS for zero-daemon requirement
   - Embedder: `sentence-transformers/all-MiniLM-L6-v2` (local, no API key)
   - LLM extraction: disabled for initial pilot (embed raw chunks, do not extract facts via LLM)
3. Verify `mem0-cli` uses this config, not its defaults

**Smoke test:** `mem0-cli add "test memory" --user-id test` followed by `mem0-cli search "test" --user-id test` returns the added memory. All data stays in `~/.mem0/` or the configured local path. `grep -r "openai\|anthropic" <actual-request-log>` finds no outbound calls.

**Pressure test:** run `mem0-cli add` with 50 memory files. Verify indexing completes in under 60 seconds on this machine. Verify `mem0-cli search` returns results in under 2 seconds.

**Acceptance criterion:** smoke test passes, pressure test passes, no API keys in env, no network calls made.

### C2: Index current memory files into mem0

**Applies only if C1 passed.**

**Goal:** write `claude/scripts/mem0_index.sh` that imports `~/.claude/memory/*.md` and the active project's `memory/*.md` into mem0 collections.

**Script behavior:**
- Accepts `--collection global` or `--collection project-<key>`
- Reads each `.md` file, strips YAML frontmatter, adds content to mem0 with `mem0-cli add`
- Idempotent: running twice does not create duplicate entries (requires checking mem0-cli for a `--deduplicate` flag or implementing an ID-based check)
- Outputs a count: `indexed N files, skipped M (already present)`

**Tests in `tests/test-memory-hooks.sh`:**
1. **Smoke:** index 1 file, verify `mem0-cli search` returns a result from it
2. **Idempotency:** index same file twice, verify search result count does not double
3. **Pressure:** index all current global memory files; verify all are retrievable; verify no file is indexed zero times

**Acceptance criterion:** all 3 tests pass. Doctor check passes.

### C3: Modify `load-global-memory.sh` for per-prompt retrieval

**Applies only if C2 passed.**

**Goal:** change `load-global-memory.sh` to inject only the MEMORY.md index on the first prompt, then call `mem0-cli search <prompt>` on every subsequent prompt to inject only relevant topical content.

**Key architectural change:** the current once-per-session marker pattern must be partially relaxed. The new behavior:
- First prompt: inject MEMORY.md index + behavioral context (as now) + set marker
- Every prompt (including first): call `mem0-cli search` with the current prompt text, inject top-3 results as an additional context block
- The per-prompt retrieval is a SECOND injection path; the marker continues to gate the full-index injection

**Implementation notes:**
- Extract `PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)`
- Call `vendor/mem0-venv/bin/mem0-cli search "$PROMPT" --user-id global --limit 3 --format json`
- Parse result and append to payload only if `mem0-cli` exits 0 and returns non-empty results
- If `mem0-cli` fails or times out (> 2 seconds), log to stderr and continue WITHOUT the retrieval results. The hook must never block on a failing external tool.

**Tests in `tests/test-memory-hooks.sh`:**
1. **Smoke:** modified hook emits valid JSON `systemMessage` on a first-prompt call
2. **Reduced injection assertion:** payload size on first-prompt is at least 30% smaller than the Phase A baseline (full-content injection). Verify by comparing char counts.
3. **Retrieval relevance (manual):** send a prompt known to match a topical file (e.g., "what are my Python conventions?"). Verify the `systemMessage` contains content from `python.md`-equivalent memory. Compare to a prompt that should NOT match it.
4. **Idempotency:** same session ID, same prompt, run hook twice. Second run still emits retrieval results (retrieval is not gated by the marker). Verify first-prompt full-index injection only fires once.
5. **Pressure - mem0-cli unavailable:** remove `mem0-cli` from PATH. Run hook. Expect it to fall back gracefully: emit the full MEMORY.md index (pre-C3 behavior), exit 0. The hook must degrade cleanly.
6. **Pressure - mem0-cli timeout:** wrap `mem0-cli` in a fake script that sleeps 10 seconds. Run hook. Expect the hook to return without the retrieval block within 3 seconds (timeout must fire).

**Acceptance criterion:** all 6 tests pass. `memory-doctor.sh` passes. Per-session injection is measurably lower than Phase A baseline.

---

## Phase D: Two-week pilot and decision gate

**Applies only if C3 passed.**

**Goal:** run the modified system in normal use for two weeks, log metrics daily, then decide.

**Metrics to log in `reports/mem0-pilot.md`:**
- Per-session global tier injection (bytes, estimated tokens)
- Per-prompt retrieval latency (seconds, from `time mem0-cli search`)
- Retrieval hit rate (subjective, 1-5 scale): did the injected memory content help the session?
- Any failures, fallbacks, or anomalies

**Pass criterion for adoption:**
- Token reduction: per-session global tier injection reduced by at least 50% vs Phase A baseline
- No observable degradation in memory recall quality across 10 test prompts targeting specific topical memories
- `mem0-cli search` p95 latency under 2 seconds in normal use

**Fail path:** revert `load-global-memory.sh` to pre-C3 state (restore from git). Remove `claude/settings.json` changes if any. Document result in `reports/mem0-pilot.md`. System reverts to Phase A state, which is already verified as working.

---

## Verification checklist (applies after every task)

Run these after completing any task before committing:

```bash
bash ~/.claude/scripts/memory-doctor.sh         # all checks A-G must pass
bash tests/run-all.sh                           # all existing suites must pass
bash tests/measure-memory-injection.sh         # measurement baseline must still run
```

No task is complete until all three commands exit 0.

---

## What is NOT in scope

- Replacing `pre-compact.sh` / `post-compact.sh` handoff system (no alternative replicates it)
- Replacing `surface-behavioral-rules.sh` (load-bearing; do not touch)
- Full system replacement with `agentmemory` or `claude-mem` (both require hook slot ownership and lack pre/post-compact handoffs)
- MCP-based integration of any tool (user constraint)
- Any change that requires an external API key to function in normal use
