#!/usr/bin/env bash
# tests/test-memory-doctor-guardrails.sh, self-testing harness for
# memory-doctor.sh checks I-M (added in tasks/plan.md T5.4).
#
# Follows the same convention as tests/test-claude-md-rules.sh: run the
# doctor on the green tree, mutate one input at a time to confirm the
# doctor catches the drift, then restore. Checks I and M touch only a
# synthetic mktemp-based project dir (never the repo's own or any real
# project's memory); checks J, K, and L temporarily mutate the real,
# git-tracked claude/memory/ tree and restore it from a backup via trap,
# exactly like test-claude-md-rules.sh does for CLAUDE.md and rules files.
#
# Usage: bash tests/test-memory-doctor-guardrails.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_DIR/claude/scripts/memory-doctor.sh"
GLOBAL_DIR="$HOME/.claude/memory"
INDEX="$GLOBAL_DIR/MEMORY.md"
PROJECTS_DIR="$HOME/.claude/projects"

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

# Backup the real, git-tracked global memory dir; restore on EXIT even on
# early failure. Checks J/K/L mutate INDEX or add/remove files in GLOBAL_DIR.
# GLOBAL_DIR is a symlink into the dotfiles repo (~/.claude/memory ->
# claude/memory/): restore must clear and repopulate its CONTENTS, never
# rm -rf the path itself, which would delete the symlink and leave a plain
# directory in its place on the next mkdir. BSD find (macOS default) also
# will not descend into a symlink given as its own starting argument, so
# operate on the realpath-resolved target, not the symlink path.
if ! GLOBAL_REAL="$(realpath "$GLOBAL_DIR")" || [ -z "$GLOBAL_REAL" ]; then
	echo "Unable to resolve global memory directory" >&2
	exit 1
fi
BACKUP_DIR=$(mktemp -d)
OUT_DIR=$(mktemp -d)
if ! cp -R "$GLOBAL_REAL"/. "$BACKUP_DIR"/; then
	rm -rf "$BACKUP_DIR" "$OUT_DIR"
	exit 1
fi
restore_global() {
	find "$GLOBAL_REAL" -mindepth 1 -maxdepth 1 -exec rm -rf {} + \
		&& cp -R "$BACKUP_DIR"/. "$GLOBAL_REAL"/
}
trap 'restore_global; rm -rf "$BACKUP_DIR" "$OUT_DIR"' EXIT

# ── 0. Doctor passes on the green tree ────────────────────────────────────
echo "# 0. Doctor on green tree"
bash "$DOCTOR" >"$OUT_DIR/green.out" 2>&1
assert "0.1 doctor exits 0 on green tree" "0" "$?"

# ── 1. Cross-tier basename collision (check I) ────────────────────────────
echo "# 1. Cross-tier basename collision"
T1_PROJ=$(mktemp -d)
T1_KEY=$(printf '%s' "$T1_PROJ" | tr '/.' '-')
T1_MEM="$PROJECTS_DIR/$T1_KEY/memory"
mkdir -p "$T1_MEM"
# Any real global file's basename creates a collision when duplicated here.
# GLOBAL_DIR is a symlink; use a glob, not find (BSD find won't descend into
# a symlink given as its own starting argument -- see GLOBAL_REAL below).
GLOBAL_BASENAME=""
for candidate in "$GLOBAL_DIR"/*.md; do
	[ -f "$candidate" ] || continue
	base="$(basename "$candidate")"
	[ "$base" = "MEMORY.md" ] && continue
	GLOBAL_BASENAME="$base"
	break
done
if [ -n "$GLOBAL_BASENAME" ]; then
	printf 'collision fixture' >"$T1_MEM/$GLOBAL_BASENAME"
	bash "$DOCTOR" >"$OUT_DIR/collision.out" 2>&1
	assert "1.1 doctor exits non-zero on cross-tier collision" "1" "$?"
	assert_contains "1.2 doctor names the collision check" "I.1 cross-tier collision" "$(cat "$OUT_DIR/collision.out")"
else
	echo "  SKIP  no global topical file to collide with"
fi
rm -rf "$T1_PROJ" "$PROJECTS_DIR/${T1_KEY:?}"

# ── 2. Unlinked file (check J.1) ───────────────────────────────────────────
echo "# 2. Unlinked global memory file"
printf -- '---\nname: orphan-fixture\ndescription: test\nmetadata:\n  type: feedback\n---\n\norphan\n' \
	>"$GLOBAL_DIR/zz_test_orphan_fixture.md"
bash "$DOCTOR" >"$OUT_DIR/unlinked.out" 2>&1
assert "2.1 doctor exits non-zero on unlinked file" "1" "$?"
assert_contains "2.2 doctor names J.1 unlinked files" "J.1 unlinked files" "$(cat "$OUT_DIR/unlinked.out")"
rm -f "$GLOBAL_DIR/zz_test_orphan_fixture.md"

# ── 3. Dead link (check J.2) ───────────────────────────────────────────────
echo "# 3. Dead link in index"
printf '\n- [Dangling](zz_test_nonexistent.md) -- fixture\n' >>"$INDEX"
bash "$DOCTOR" >"$OUT_DIR/deadlink.out" 2>&1
assert "3.1 doctor exits non-zero on dead link" "1" "$?"
assert_contains "3.2 doctor names J.2 dead links" "J.2 dead links" "$(cat "$OUT_DIR/deadlink.out")"
restore_global

# ── 4. Filename lint (check K) ─────────────────────────────────────────────
echo "# 4. Filename the index-link regex cannot match"
printf -- '---\nname: bad-name-fixture\ndescription: test\nmetadata:\n  type: feedback\n---\n\nfixture\n' \
	>"$GLOBAL_DIR/zz test with spaces.md"
bash "$DOCTOR" >"$OUT_DIR/badname.out" 2>&1
assert "4.1 doctor exits non-zero on unmatchable filename" "1" "$?"
assert_contains "4.2 doctor names K.1 filename lint" "K.1 filename lint" "$(cat "$OUT_DIR/badname.out")"
rm -f "$GLOBAL_DIR/zz test with spaces.md"

# ── 5. Payload budget (check L) ────────────────────────────────────────────
echo "# 5. Payload exceeds the 2k token budget"
python3 -c "print('x' * 8000)" >"$GLOBAL_DIR/zz_test_oversized.md" 2>/dev/null \
	|| yes x | head -c 8000 >"$GLOBAL_DIR/zz_test_oversized.md"
printf '\n- [Oversized](zz_test_oversized.md) -- fixture\n' >>"$INDEX"
bash "$DOCTOR" >"$OUT_DIR/budget.out" 2>&1
assert "5.1 doctor exits non-zero over the 2k token budget" "1" "$?"
assert_contains "5.2 doctor names L.1 payload budget" "L.1 payload budget" "$(cat "$OUT_DIR/budget.out")"
restore_global

# ── 6. Pending migration (check M) ─────────────────────────────────────────
echo "# 6. Project tier holding an unmigrated user_*.md file"
T6_PROJ=$(mktemp -d)
T6_KEY=$(printf '%s' "$T6_PROJ" | tr '/.' '-')
T6_MEM="$PROJECTS_DIR/$T6_KEY/memory"
mkdir -p "$T6_MEM"
printf 'unmigrated stub' >"$T6_MEM/user_pending_fixture.md"
bash "$DOCTOR" >"$OUT_DIR/pending.out" 2>&1
assert "6.1 doctor exits non-zero on pending migration" "1" "$?"
assert_contains "6.2 doctor names M.1 pending migration" "M.1 pending migration" "$(cat "$OUT_DIR/pending.out")"
rm -rf "$T6_PROJ" "$PROJECTS_DIR/${T6_KEY:?}"

# ── 7. Receipt detection (check H) ─────────────────────────────────────────
# Regression fixture for a real bug found via a live headless (`claude -p`)
# session: CC 2.1.207 logs SessionStart's additionalContext as a
# {"type":"attachment","attachment":{"type":"hook_additional_context", ...}}
# record, never as a "user"-role message, and the original H.1 only looked at
# "user" records. A second bug compounded it: picking "the newest transcript
# by mtime" always selects whichever session is currently running the
# doctor, which structurally never carries fresh evidence once resumed (see
# memory-doctor.sh's H section comment). REPO_DIR is hardcoded from the
# script's own path, so isolating this check needs the doctor's
# MEMORY_DOCTOR_TRANSCRIPTS_DIR override instead. These fixtures pin the
# fixed detection: a genuine attachment record is a hit; an assistant merely
# quoting the header text, or a tool_result from manually invoking the hook,
# are not.
echo "# 7. Receipt detection (check H)"
T7_TRANSCRIPTS=$(mktemp -d)

# 7a. No transcript at all: skip, not fail.
OUT=$(MEMORY_DOCTOR_TRANSCRIPTS_DIR="$T7_TRANSCRIPTS" bash "$DOCTOR" 2>&1)
assert_contains "7a.1 no transcript skips H.1" "H.1 skipped" "$OUT"

# 7b. Decoy: assistant text quoting the header literally (e.g. writing the
# hook's own source) must not count as receipt.
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"## Global memory (cross-project, user-level) is the header this hook writes"}]}}\n' \
	>"$T7_TRANSCRIPTS/decoy-assistant.jsonl"
OUT=$(MEMORY_DOCTOR_TRANSCRIPTS_DIR="$T7_TRANSCRIPTS" bash "$DOCTOR" 2>&1)
assert_contains "7b.1 assistant-text decoy still skips H.1" "H.1 skipped" "$OUT"

# 7c. Decoy: a tool_result from manually invoking the hook via Bash must not
# count either.
printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"## Global memory (cross-project, user-level)\\n..."}]},"toolUseResult":{}}\n' \
	>>"$T7_TRANSCRIPTS/decoy-assistant.jsonl"
OUT=$(MEMORY_DOCTOR_TRANSCRIPTS_DIR="$T7_TRANSCRIPTS" bash "$DOCTOR" 2>&1)
assert_contains "7c.1 tool_result decoy still skips H.1" "H.1 skipped" "$OUT"

# 7d. Genuine record: the real attachment shape CC 2.1.207 emits.
printf '{"type":"attachment","attachment":{"type":"hook_additional_context","hookEvent":"SessionStart","hookName":"SessionStart","content":["## Global memory (cross-project, user-level)\\n\\nfixture payload"]},"timestamp":"2026-01-01T00:00:00.000Z"}\n' \
	>"$T7_TRANSCRIPTS/genuine.jsonl"
OUT=$(MEMORY_DOCTOR_TRANSCRIPTS_DIR="$T7_TRANSCRIPTS" bash "$DOCTOR" 2>&1)
assert_contains "7d.1 genuine attachment record is detected as receipt" "H.1 a real transcript carries a genuine SessionStart additionalContext attachment" "$OUT"

rm -rf "$T7_TRANSCRIPTS"

# ── 8. Doctor passes again after all restores ──────────────────────────────
echo "# 8. Restore"
bash "$DOCTOR" >/dev/null 2>&1
assert "8.1 doctor exits 0 after restore" "0" "$?"

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "test-memory-doctor-guardrails: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
