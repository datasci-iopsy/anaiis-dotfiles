# Memory System Evolution: Task List

Status: [ ] = not started | [~] = in progress | [x] = done | [skip] = skipped per decision gate

---

## Phase A: Measure injection cost

- [ ] **A1** Write `tests/measure-memory-injection.sh`
  - [ ] Hook emits valid JSON (smoke)
  - [ ] Second call with same session ID is silent (idempotency assertion)
  - [ ] Missing MEMORY.md exits 0 silently (pressure)
  - [ ] Invalid session_id with path chars exits 0 silently (pressure)
  - [ ] Missing jq exits 0 silently (pressure)
  - [ ] Script writes `reports/memory-cost-baseline.md` with global + project byte/token counts
  - [ ] `tests/run-all.sh` passes after adding the new test file

- [ ] **A-GATE** Review `reports/memory-cost-baseline.md`
  - [ ] If total estimated tokens < 5,000: mark Phases C0-D as [skip], stop here
  - [ ] If total estimated tokens >= 5,000: continue to Phase C0

---

## Phase B: Local fixes (independent of Phase A result)

- [ ] **B1** Fix `seed-memory.sh:46` encoding divergence
  - [ ] Edit line 46: `ENCODED=$(echo "$PROJECT_PATH" | tr '/.' '-')`
  - [ ] Add test to `tests/test-memory-hooks.sh` (create new file if absent)
    - [ ] Smoke: script exits 0 on clean tmpdir
    - [ ] Key assertion: dot-containing path produces same key as `tr '/.' '-'`
    - [ ] Pressure: multiple dots + slashes, key parity with hooks
    - [ ] Regression: no-dot path produces same key as before fix
  - [ ] `bash ~/.claude/scripts/memory-doctor.sh` exits 0, all A-G pass
  - [ ] `tests/run-all.sh` passes

- [ ] **B2** Add `--prune-markers` to `cleanup-sessions.py`
  - [ ] Implement flag: collect orphaned `/tmp/claude-session-*.{global,behavioral}-loaded` markers
  - [ ] Add test to `tests/test-memory-hooks.sh`
    - [ ] Smoke: `--prune-markers --dry-run` exits 0 with no markers present
    - [ ] Key assertion: orphan markers removed; non-marker `/tmp/` files untouched
    - [ ] Live session guard: marker for active session NOT removed
    - [ ] Pressure: restricted permissions handled gracefully (non-zero exit or error report)
  - [ ] `bash ~/.claude/scripts/memory-doctor.sh` exits 0, all A-G pass
  - [ ] `tests/run-all.sh` passes

---

## Phase C: CLI viability gate (skip if A-GATE found < 5k tokens)

- [ ] **C0** Verify `mem0-cli` has usable recall CLI
  - [ ] `pipx install mem0ai` OR `uv tool install mem0ai` succeeds
  - [ ] `mem0-cli --help` shows a search/recall/query subcommand
  - [ ] `mem0-cli search "test query"` returns JSON output
  - [ ] JSON output contains memory result text fields
  - [ ] All of above works without `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`
  - [ ] Document findings in `reports/mem0-pilot.md`
  - [ ] **C0-GATE**: if any check fails, mark C1-D as [skip]; document stop reason in `reports/mem0-pilot.md`

- [ ] **C1** Configure mem0 for local-only operation
  - [ ] Create `vendor/mem0-venv/` via `uv venv + uv pip install mem0ai sentence-transformers`
  - [ ] Create `claude/config/mem0.yaml` (FAISS vector store, local MiniLM embedder, LLM extraction disabled)
  - [ ] Smoke test: add a memory, search for it, verify result; no network calls made
  - [ ] Pressure test: 50 files indexed in < 60 seconds; search returns in < 2 seconds
  - [ ] Verify: no `openai` or `anthropic` endpoints called (confirm with network monitor or env var absence test)

- [ ] **C2** Write `claude/scripts/mem0_index.sh`
  - [ ] Script accepts `--collection global` and `--collection project-<key>`
  - [ ] Strips YAML frontmatter before indexing each file
  - [ ] Idempotent (second run does not duplicate entries)
  - [ ] Outputs indexed/skipped count
  - [ ] Smoke: index 1 file, search returns it
  - [ ] Idempotency test: index same file twice, result count unchanged
  - [ ] Pressure: index all global memory files; all retrievable

- [ ] **C3** Modify `claude/hooks/load-global-memory.sh` for per-prompt retrieval
  - [ ] First prompt: inject MEMORY.md index only (not full topical content), set marker as before
  - [ ] Every prompt: call `mem0-cli search <prompt>` via `vendor/mem0-venv/`, inject top-3 results
  - [ ] Timeout guard: if `mem0-cli` takes > 2s, skip retrieval block, continue
  - [ ] Failure guard: if `mem0-cli` fails, fall back to full-content injection (pre-C3 behavior)
  - [ ] Tests in `tests/test-memory-hooks.sh`:
    - [ ] Smoke: hook emits valid `systemMessage` JSON
    - [ ] Reduced injection: payload is at least 30% smaller than Phase A baseline
    - [ ] Retrieval relevance (manual): known-match prompt returns topical content
    - [ ] Idempotency: marker still gates full-index injection to first prompt only
    - [ ] Pressure - unavailable: mem0-cli not on PATH, hook falls back cleanly
    - [ ] Pressure - timeout: fake mem0-cli with 10s sleep, hook returns within 3s
  - [ ] `memory-doctor.sh` exits 0, all A-G pass
  - [ ] `tests/run-all.sh` passes
  - [ ] Per-session injection measurably lower than Phase A baseline (document in `reports/mem0-pilot.md`)

---

## Phase D: Two-week pilot and decision gate (skip if C3 not reached)

- [ ] **D1** Run normal sessions for 2 weeks; log daily in `reports/mem0-pilot.md`
  - [ ] Per-session global tier injection (bytes, tokens)
  - [ ] Per-prompt retrieval latency (p50, p95)
  - [ ] Retrieval hit rate (subjective, 1-5 scale per session)
  - [ ] Any failures or fallbacks

- [ ] **D-GATE** Evaluate pilot results
  - [ ] Pass: token reduction >= 50% vs Phase A baseline AND no observable recall degradation
    - [ ] Update `reports/memory-workflow.qmd` to document augmentation
    - [ ] Add check H to `memory-doctor.sh` for mem0 health
    - [ ] Commit to branch and merge via normal flow
  - [ ] Fail: revert `load-global-memory.sh` to pre-C3 state
    - [ ] Remove any `claude/settings.json` changes (if any)
    - [ ] Document findings in `reports/mem0-pilot.md`
    - [ ] System returns to Phase A state (verified working)

---

## Always run after any change

```bash
bash ~/.claude/scripts/memory-doctor.sh   # checks A-G must all pass
bash tests/run-all.sh                     # all suites must pass
```
