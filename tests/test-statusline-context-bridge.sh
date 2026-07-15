#!/usr/bin/env bash
# tests/test-statusline-context-bridge.sh -- statusline-command.sh writes the
# harness's exact context_window.used_percentage to a per-session /tmp file
# so context-watch.sh (a PostToolUse hook, which receives no context metrics
# of its own) can detect the 60% compaction threshold deterministically.
# See tasks/plan.md T2.1.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_DIR/claude/scripts/statusline-command.sh"

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
	[ "$got" = "$want" ] && pass "$label" || fail "$label (got: '$got', want: '$want')"
}

assert_file_absent() {
	local label="$1" path="$2"
	[ ! -f "$path" ] && pass "$label" || fail "$label (file should not exist: $path)"
}

strip_ansi() {
	sed -E 's/\x1b\[[0-9;]*m//g'
}

make_input() {
	local pct="$1" sid="$2"
	jq -n --arg sid "$sid" --argjson pct "$pct" \
		'{"session_id": $sid, "model": {"id": "claude-sonnet-5"},
		  "context_window": {"used_percentage": $pct, "current_usage": {"input_tokens": 100, "output_tokens": 50}},
		  "workspace": {"current_dir": "/tmp"}}'
}

# ---- T1: pct file written with the exact harness value ---------------------

echo
echo "--- T1: pct file written with exact context_window.used_percentage"

T1_SID="statustest-$$-1"
T1_PCT_FILE="/tmp/claude-context-${T1_SID}.pct"
rm -f "$T1_PCT_FILE"

make_input 42 "$T1_SID" | bash "$SCRIPT" >/dev/null 2>&1 || true

if [ -f "$T1_PCT_FILE" ]; then
	assert_eq "T1: pct file contains 42" "$(cat "$T1_PCT_FILE")" "42"
else
	fail "T1: pct file not written at $T1_PCT_FILE"
fi
rm -f "$T1_PCT_FILE"

# ---- T2: no marker below 60% ------------------------------------------------

echo
echo "--- T2: no compact marker below 60%"

T2_SID="statustest-$$-2"
T2_OUT=$(make_input 45 "$T2_SID" | bash "$SCRIPT" 2>/dev/null | strip_ansi)
rm -f "/tmp/claude-context-${T2_SID}.pct"

if printf '%s' "$T2_OUT" | grep -q 'compact:60+'; then
	fail "T2: compact marker present below 60%"
else
	pass "T2: no compact marker below 60%"
fi

# ---- T3: marker present at and above 60% ------------------------------------

echo
echo "--- T3: compact marker present at 60% and above"

T3_SID="statustest-$$-3"
T3_OUT=$(make_input 60 "$T3_SID" | bash "$SCRIPT" 2>/dev/null | strip_ansi)
rm -f "/tmp/claude-context-${T3_SID}.pct"

if printf '%s' "$T3_OUT" | grep -q 'compact:60+'; then
	pass "T3: compact marker present at 60%"
else
	fail "T3: compact marker missing at 60%"
fi

# ---- T4: path-unsafe session_id is rejected --------------------------------

echo
echo "--- T4: pressure - path-unsafe session_id writes nothing"

T4_UNSAFE_FILE="/tmp/claude-context-../evil.pct"
rm -f "$T4_UNSAFE_FILE"
make_input 70 "../evil" | bash "$SCRIPT" >/dev/null 2>&1 || true
assert_file_absent "T4: no pct file written for unsafe session_id" "$T4_UNSAFE_FILE"

# ---- T5: missing session_id is a graceful no-op for the pct file -----------

echo
echo "--- T5: pressure - missing session_id, statusline still renders"

T5_OUT=$(jq -n '{"model": {"id": "claude-sonnet-5"}, "context_window": {"used_percentage": 30}, "workspace": {"current_dir": "/tmp"}}' \
	| bash "$SCRIPT" 2>/dev/null)
if [ -n "$T5_OUT" ]; then
	pass "T5: statusline still renders without session_id"
else
	fail "T5: statusline produced no output without session_id"
fi

# ---- Summary ----------------------------------------------------------------

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
