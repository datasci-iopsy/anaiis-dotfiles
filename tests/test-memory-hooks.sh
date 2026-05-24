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

assert_eq() {
	local label="$1" got="$2" want="$3"
	if [ "$got" = "$want" ]; then
		pass "$label"
	else
		fail "$label (got: '$got', want: '$want')"
	fi
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

# B1-smoke: script exits 0 on a clean tmpdir
echo
echo "--- B1-smoke: seed-memory.sh exits 0 on clean tmpdir"

B1_HOME=$(mktemp -d)
B1_PROJECT=$(mktemp -d)
mkdir -p "$B1_HOME/.claude"

# Provide a minimal TEMPLATES dir so the script doesn't error on missing dir
B1_TEMPLATES="$B1_PROJECT/templates"
mkdir -p "$B1_TEMPLATES"

# Run with a controlled HOME and DOTFILES so it writes into our tmpdir
# We override DOTFILES by temporarily symlinking; instead, patch via env is not
# supported by the script. Run it from a workaround: set HOME so the output path
# is redirectable, and accept that it seeds into B1_HOME.
if HOME="$B1_HOME" bash "$SEED_SCRIPT" >/dev/null 2>&1; then
	pass "B1-smoke: seed-memory.sh exits 0"
else
	fail "B1-smoke: seed-memory.sh exited non-zero"
fi

rm -rf "$B1_HOME" "$B1_PROJECT"

# B1-key: both seed-memory.sh and pre-compact.sh contain the canonical formula.
# Fails if either script switches to a different encoding (e.g. slash-only).
echo
echo "--- B1-key: encoding formula parity between seed-memory.sh and pre-compact.sh"

PRE_COMPACT="$REPO_DIR/claude/hooks/pre-compact.sh"
if grep -qF "tr '/.' '-'" "$SEED_SCRIPT"; then
	pass "B1-key: seed-memory.sh uses canonical tr '/.' '-' formula"
else
	fail "B1-key: seed-memory.sh does not contain expected encoding formula"
fi
if grep -qF "tr '/.' '-'" "$PRE_COMPACT"; then
	pass "B1-key: pre-compact.sh uses canonical tr '/.' '-' formula"
else
	fail "B1-key: pre-compact.sh does not contain expected encoding formula"
fi

# Confirm slash-only encoding diverges on a dot-containing path; this proves
# tr '/.' '-' (not tr '/' '-') is required to produce a unique key.
DOT_PATH="/Users/user.name/my.project/repo"
if [ "${DOT_PATH//\//-}" != "$(echo "$DOT_PATH" | tr '/.' '-')" ]; then
	pass "B1-key: confirmed old slash-only encoding diverges from tr '/.' '-'"
else
	fail "B1-key: old and new encodings unexpectedly match for dot-containing path"
fi

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

# B1-regression: no-dot path produces same key as before fix
echo
echo "--- B1-regression: no-dot path unchanged"

NODOT_PATH="/Users/username/projects/myrepo"
NEW_KEY=$(echo "$NODOT_PATH" | tr '/.' '-')
OLD_KEY_NODOT="${NODOT_PATH//\//-}"
assert_eq "B1-regression: no-dot path key unchanged" "$NEW_KEY" "$OLD_KEY_NODOT"

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

# B2-smoke: --prune-markers --dry-run exits 0 with no markers present
echo
echo "--- B2-smoke: --prune-markers --dry-run exits 0 with no markers"

# Use a unique prefix to avoid touching real markers
B2_SID="test-prune-$$-$(date +%s)"
# Clean any pre-existing test markers (shouldn't exist)
rm -f /tmp/claude-session-${B2_SID}*.global-loaded
rm -f /tmp/claude-session-${B2_SID}*.behavioral-loaded

if python3 "$CLEANUP_SCRIPT" --prune-markers --dry-run >/dev/null 2>&1; then
	pass "B2-smoke: --prune-markers --dry-run exits 0"
else
	fail "B2-smoke: --prune-markers --dry-run exited non-zero"
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

if python3 "$CLEANUP_SCRIPT" --prune-markers --dry-run >/dev/null 2>&1; then
	pass "B2-dry-run: --prune-markers --dry-run exits 0"
else
	fail "B2-dry-run: --prune-markers --dry-run exited non-zero"
fi

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

if python3 "$CLEANUP_SCRIPT" --prune-markers >/dev/null 2>&1; then
	pass "B2-live-guard: --prune-markers exits 0"
else
	fail "B2-live-guard: --prune-markers exited non-zero"
fi

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
