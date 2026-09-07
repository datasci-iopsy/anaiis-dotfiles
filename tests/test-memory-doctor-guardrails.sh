#!/usr/bin/env bash
# tests/test-memory-doctor-guardrails.sh, self-testing harness for
# memory-doctor.sh checks H-M.
#
# Run the doctor on a green tree, then apply every drift fixture at once and
# confirm the doctor names each targeted check. One multi-fault run rather
# than one run per fault: the doctor runs every check and never exits early,
# so each name assertion pins its own check (deleting check X removes the
# "X" line from the output), and a single exit-code assertion covers the
# shared FAIL plumbing. The per-fault exit-code assertions this replaced
# could not fail independently: most fixtures also trip B.1 (no frontmatter)
# or J.1 (unlinked), so the doctor exited 1 even with the targeted check
# deleted (tasks/trim-candidates.md, 2026-09-07). Check H keeps one run per
# transcript state because each state is a distinct regression fixture.
#
# Hermetic by construction. The doctor derives its repo root from its own
# path and its global tier from $HOME/.claude/memory, and check A.1 requires
# the second to be a symlink into the first. So every run here points the
# doctor at a throwaway copy of claude/memory and claude/hooks (via
# MEMORY_DOCTOR_REPO_DIR) under a throwaway HOME whose .claude/memory links
# into that copy, with MEMORY_DOCTOR_TRANSCRIPTS_DIR set on every run. The
# real ~/.claude tree, the real git-tracked claude/memory/, and this
# machine's session transcripts are never read or written, so results are
# identical on a loaded dev machine and on a clean CI runner.
#
# Usage: bash tests/test-memory-doctor-guardrails.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_DIR/claude/scripts/memory-doctor.sh"

PASS=0
FAIL=0

assert() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

assert_contains() {
	local name="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected to contain: %s\n' "$name" "$needle"
		FAIL=$((FAIL + 1))
	fi
}

# ── Fixture: throwaway repo copy + throwaway HOME ──────────────────────────
# Resolve the fixture root with pwd -P once: macOS mktemp returns a
# /var/folders path that resolves to /private/var, and the doctor's A.1
# compares the resolved symlink target against $REPO_DIR/claude/memory as a
# string, so both sides must already be in resolved form.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

TMP_REPO="$WORK/repo"
TMP_HOME="$WORK/home"
TMP_TRANSCRIPTS="$WORK/transcripts"
OUT_DIR="$WORK/out"
mkdir -p "$TMP_REPO/claude" "$TMP_HOME/.claude/projects" "$TMP_TRANSCRIPTS" "$OUT_DIR"
cp -R "$REPO_DIR/claude/memory" "$TMP_REPO/claude/memory"
cp -R "$REPO_DIR/claude/hooks" "$TMP_REPO/claude/hooks"
ln -s "$TMP_REPO/claude/memory" "$TMP_HOME/.claude/memory"

GLOBAL_DIR="$TMP_HOME/.claude/memory"
INDEX="$GLOBAL_DIR/MEMORY.md"
PROJECTS_DIR="$TMP_HOME/.claude/projects"

# run_doctor <outfile> [transcripts-dir]: every doctor invocation goes
# through here so no run can fall back to the real HOME, repo, or transcripts.
run_doctor() {
	local out="$1" transcripts="${2:-$TMP_TRANSCRIPTS}"
	HOME="$TMP_HOME" \
		MEMORY_DOCTOR_REPO_DIR="$TMP_REPO" \
		MEMORY_DOCTOR_TRANSCRIPTS_DIR="$transcripts" \
		bash "$DOCTOR" >"$out" 2>&1
}

# Reset the throwaway memory copy to the real tree's content. The HOME-side
# symlink points at the directory path, so replacing the directory's
# contents keeps the link valid.
restore_global() {
	rm -rf "$TMP_REPO/claude/memory"
	cp -R "$REPO_DIR/claude/memory" "$TMP_REPO/claude/memory"
}

# ── 0. Doctor passes on the green tree ────────────────────────────────────
echo "# 0. Doctor on green tree"
run_doctor "$OUT_DIR/green.out"
assert "0.1 doctor exits 0 on green tree" "0" "$?"

# ── 1. Every drift fixture at once (checks I, J.1, J.2, K, L, M) ──────────
echo "# 1. Every drift fixture applied at once"
# I: a project-tier file sharing a basename with a global file. GLOBAL_DIR
# is a symlink; use a glob, not find (BSD find won't descend into a symlink
# given as its own starting argument).
T1_PROJ=$(mktemp -d)
T1_KEY=$(printf '%s' "$T1_PROJ" | tr '/.' '-')
T1_MEM="$PROJECTS_DIR/$T1_KEY/memory"
mkdir -p "$T1_MEM"
GLOBAL_BASENAME=""
for candidate in "$GLOBAL_DIR"/*.md; do
	[ -f "$candidate" ] || continue
	base="$(basename "$candidate")"
	[ "$base" = "MEMORY.md" ] && continue
	GLOBAL_BASENAME="$base"
	break
done
[ -n "$GLOBAL_BASENAME" ] && printf 'collision fixture' >"$T1_MEM/$GLOBAL_BASENAME"
# J.1: a global file the index does not link
printf -- '---\nname: orphan-fixture\ndescription: test\nmetadata:\n  type: feedback\n---\n\norphan\n' \
	>"$GLOBAL_DIR/zz_test_orphan_fixture.md"
# J.2: an index link to a file that does not exist
printf '\n- [Dangling](zz_test_nonexistent.md) -- fixture\n' >>"$INDEX"
# K: a filename the index-link regex cannot match
printf -- '---\nname: bad-name-fixture\ndescription: test\nmetadata:\n  type: feedback\n---\n\nfixture\n' \
	>"$GLOBAL_DIR/zz test with spaces.md"
# L: a linked file large enough to blow the 2k token budget
python3 -c "print('x' * 8000)" >"$GLOBAL_DIR/zz_test_oversized.md" 2>/dev/null \
	|| yes x | head -c 8000 >"$GLOBAL_DIR/zz_test_oversized.md"
printf '\n- [Oversized](zz_test_oversized.md) -- fixture\n' >>"$INDEX"
# M: a project-tier user_*.md awaiting migration
printf 'unmigrated stub' >"$T1_MEM/user_pending_fixture.md"

run_doctor "$OUT_DIR/faults.out"
RC=$?
OUT=$(cat "$OUT_DIR/faults.out")
assert "1.1 doctor exits non-zero with every fault present" "1" "$RC"
if [ -n "$GLOBAL_BASENAME" ]; then
	assert_contains "1.2 doctor names the collision check (I.1)" "I.1 cross-tier collision" "$OUT"
else
	echo "  SKIP  1.2 no global topical file to collide with"
fi
assert_contains "1.3 doctor names unlinked files (J.1)" "J.1 unlinked files" "$OUT"
assert_contains "1.4 doctor names dead links (J.2)" "J.2 dead links" "$OUT"
assert_contains "1.5 doctor names filename lint (K.1)" "K.1 filename lint" "$OUT"
assert_contains "1.6 doctor names the payload budget (L.1)" "L.1 payload budget" "$OUT"
assert_contains "1.7 doctor names pending migration (M.1)" "M.1 pending migration" "$OUT"

rm -rf "$T1_PROJ" "$PROJECTS_DIR/${T1_KEY:?}"
restore_global

# ── 7. Receipt detection (check H) ─────────────────────────────────────────
# Regression fixture for a real bug found via a live headless (`claude -p`)
# session: CC 2.1.207 logs SessionStart's additionalContext as a
# {"type":"attachment","attachment":{"type":"hook_additional_context", ...}}
# record, never as a "user"-role message, and the original H.1 only looked at
# "user" records. A second bug compounded it: picking "the newest transcript
# by mtime" always selects whichever session is currently running the
# doctor, which structurally never carries fresh evidence once resumed (see
# memory-doctor.sh's H section comment). These fixtures pin the fixed
# detection: a genuine attachment record is a hit; an assistant merely
# quoting the header text, or a tool_result from manually invoking the hook,
# are not. Ids keep their historical "7" prefix so history stays greppable.
echo "# 7. Receipt detection (check H)"
T7_TRANSCRIPTS="$WORK/transcripts-7"
mkdir -p "$T7_TRANSCRIPTS"

# 7a. No transcript at all: skip, not fail.
run_doctor "$OUT_DIR/7a.out" "$T7_TRANSCRIPTS"
assert_contains "7a.1 no transcript skips H.1" "H.1 skipped" "$(cat "$OUT_DIR/7a.out")"

# 7b. Decoy: assistant text quoting the header literally (e.g. writing the
# hook's own source) must not count as receipt.
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"## Global memory (cross-project, user-level) is the header this hook writes"}]}}\n' \
	>"$T7_TRANSCRIPTS/decoy-assistant.jsonl"
run_doctor "$OUT_DIR/7b.out" "$T7_TRANSCRIPTS"
assert_contains "7b.1 assistant-text decoy still skips H.1" "H.1 skipped" "$(cat "$OUT_DIR/7b.out")"

# 7c. Decoy: a tool_result from manually invoking the hook via Bash must not
# count either.
printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"## Global memory (cross-project, user-level)\\n..."}]},"toolUseResult":{}}\n' \
	>>"$T7_TRANSCRIPTS/decoy-assistant.jsonl"
run_doctor "$OUT_DIR/7c.out" "$T7_TRANSCRIPTS"
assert_contains "7c.1 tool_result decoy still skips H.1" "H.1 skipped" "$(cat "$OUT_DIR/7c.out")"

# 7d. Genuine record: the real attachment shape CC 2.1.207 emits.
printf '{"type":"attachment","attachment":{"type":"hook_additional_context","hookEvent":"SessionStart","hookName":"SessionStart","content":["## Global memory (cross-project, user-level)\\n\\nfixture payload"]},"timestamp":"2026-01-01T00:00:00.000Z"}\n' \
	>"$T7_TRANSCRIPTS/genuine.jsonl"
run_doctor "$OUT_DIR/7d.out" "$T7_TRANSCRIPTS"
assert_contains "7d.1 genuine attachment record is detected as receipt" "H.1 a real transcript carries a genuine SessionStart additionalContext attachment" "$(cat "$OUT_DIR/7d.out")"

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "test-memory-doctor-guardrails: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
