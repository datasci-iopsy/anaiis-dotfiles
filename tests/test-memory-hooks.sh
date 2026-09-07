#!/usr/bin/env bash
# tests/test-memory-hooks.sh -- test memory hook supporting scripts
#
# B1: seed-memory.sh encoding parity with hooks (tr '/.' '-')
# B2: cleanup-sessions.py --prune-markers
#
# Exit 0 if all tests pass; non-zero on any failure.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEED_SCRIPT="$REPO_DIR/claude/scripts/seed-memory.sh"
CLEANUP_SCRIPT="$REPO_DIR/claude/scripts/cleanup-sessions.py"

PASS=0
FAIL=0

pass() {
	echo "  PASS  $1"
	PASS=$((PASS + 1))
}

fail() {
	echo "  FAIL  $1"
	FAIL=$((FAIL + 1))
}

assert_empty() {
	local label="$1" value="$2"
	[ -z "$value" ] \
		&& pass "$label" \
		|| fail "$label (expected empty, got: ${value:0:80})"
}

assert_file_exists() {
	local label="$1" path="$2"
	[ -f "$path" ] \
		&& pass "$label" \
		|| fail "$label (file not found: $path)"
}

assert_file_absent() {
	local label="$1" path="$2"
	[ ! -f "$path" ] \
		&& pass "$label" \
		|| fail "$label (file should not exist: $path)"
}

# ── B1: seed-memory.sh encoding parity ────────────────────────────────────────

echo
echo "--- B1: seed-memory.sh encoding key parity with tr '/.' '-'"

# Helper: extract the project key that seed-memory.sh would compute for a given path.
# We source only the encoding line in a subshell to avoid side effects.
seed_key_for() {
	local path="$1"
	echo "$path" | tr '/.' '-'
}

hooks_key_for() {
	local path="$1"
	echo "$path" | tr '/.' '-'
}

# B1-pressure: seed-memory.sh creates the project dir at the tr '/.' '-' encoded path.
# Runs the real script, verifies the directory it creates matches the formula.
echo
echo "--- B1-pressure: seed-memory.sh writes to tr '/.' '-' encoded directory"

B1P_HOME=$(mktemp -d)
B1P_PROJ=$(mktemp -d)
B1P_DOTTED="$B1P_PROJ/my.project.name"
mkdir -p "$B1P_DOTTED"

B1P_REALPATH=$(cd "$B1P_DOTTED" && pwd)
(cd "$B1P_DOTTED" && HOME="$B1P_HOME" bash "$SEED_SCRIPT" >/dev/null 2>&1) || true

EXPECTED_KEY=$(echo "$B1P_REALPATH" | tr '/.' '-')
EXPECTED_DIR="$B1P_HOME/.claude/projects/$EXPECTED_KEY/memory"

if [ -d "$EXPECTED_DIR" ]; then
	pass "B1-pressure: seed-memory.sh creates dir at tr '/.' '-' encoded path"
else
	ACTUAL_DIRS=$(ls "$B1P_HOME/.claude/projects/" 2>/dev/null || echo "no projects dir")
	fail "B1-pressure: expected dir not found (key: $EXPECTED_KEY, actual: $ACTUAL_DIRS)"
fi

rm -rf "$B1P_HOME" "$B1P_PROJ"

# ── B2: cleanup-sessions.py --prune-markers ───────────────────────────────────

echo
echo "--- B2: cleanup-sessions.py --prune-markers"

if [ ! -f "$CLEANUP_SCRIPT" ]; then
	echo "  SKIP  cleanup-sessions.py not found at $CLEANUP_SCRIPT"
	echo
	echo "============================================================"
	echo "  Tests passed: $PASS"
	echo "  Tests failed: $FAIL"
	echo
	[ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

# B2-key: orphan markers removed; non-marker /tmp/ files untouched
echo
echo "--- B2-key: orphan markers removed, sentinel untouched"

ORPHAN_SID="orphan-$$-$(date +%s)"
ORPHAN_MARKER="/tmp/claude-session-${ORPHAN_SID}.global-loaded"
SENTINEL="/tmp/test-sentinel-${ORPHAN_SID}.txt"

touch "$ORPHAN_MARKER"
touch "$SENTINEL"

if python3 "$CLEANUP_SCRIPT" --prune-markers >/dev/null 2>&1; then
	pass "B2-key: --prune-markers exits 0"
else
	fail "B2-key: --prune-markers exited non-zero"
fi

assert_file_absent "B2-key: orphan marker removed" "$ORPHAN_MARKER"
assert_file_exists "B2-key: non-marker sentinel untouched" "$SENTINEL"

rm -f "$ORPHAN_MARKER" "$SENTINEL"

# B2-dry-run: --dry-run leaves markers in place
echo
echo "--- B2-dry-run: --dry-run does not remove markers"

DRY_SID="dryrun-$$-$(date +%s)"
DRY_MARKER="/tmp/claude-session-${DRY_SID}.global-loaded"
touch "$DRY_MARKER"

python3 "$CLEANUP_SCRIPT" --prune-markers --dry-run >/dev/null 2>&1 || true

assert_file_exists "B2-dry-run: marker preserved under --dry-run" "$DRY_MARKER"
rm -f "$DRY_MARKER"

# B2-live-guard: marker whose session_id has a JSONL is preserved
echo
echo "--- B2-live-guard: active session marker preserved"

LIVE_SID="liveguard-$$-$(date +%s)"
LIVE_MARKER="/tmp/claude-session-${LIVE_SID}.global-loaded"
LIVE_PROJ_DIR="$HOME/.claude/projects/test-live-prune-${LIVE_SID}"
mkdir -p "$LIVE_PROJ_DIR"
echo '{"type":"user"}' >"$LIVE_PROJ_DIR/${LIVE_SID}.jsonl"
touch "$LIVE_MARKER"

python3 "$CLEANUP_SCRIPT" --prune-markers >/dev/null 2>&1 || true

assert_file_exists "B2-live-guard: marker with live JSONL preserved" "$LIVE_MARKER"

rm -f "$LIVE_MARKER" "$LIVE_PROJ_DIR/${LIVE_SID}.jsonl"
rmdir "$LIVE_PROJ_DIR"

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
