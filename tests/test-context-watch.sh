#!/usr/bin/env bash
# tests/test-context-watch.sh -- context-watch.sh, a PostToolUse hook that
# reads the pct file statusline-command.sh writes and, at >=60% context,
# emits a one-shot additionalContext directive to checkpoint and request
# /compact. No native harness knob triggers compaction at a chosen threshold
# (only ~85% auto-compact), so this is the closest deterministic mechanism.
# See tasks/plan.md T2.1.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/context-watch.sh"

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
	[ -z "$value" ] && pass "$label" || fail "$label (expected empty, got: ${value:0:120})"
}

assert_contains() {
	local label="$1" haystack="$2" needle="$3"
	printf '%s' "$haystack" | grep -qF "$needle" && pass "$label" || fail "$label (missing: $needle)"
}

if [ ! -f "$HOOK" ]; then
	echo "  FAIL  hook not found at $HOOK"
	echo
	echo "============================================================"
	echo "  Tests passed: 0"
	echo "  Tests failed: 1"
	exit 1
fi

make_input() {
	local sid="$1"
	jq -n --arg sid "$sid" '{"session_id": $sid, "hook_event_name": "PostToolUse", "tool_name": "Read"}'
}

# ---- T1: below 60% is a no-op ------------------------------------------------

echo
echo "--- T1: below 60% emits nothing"

T1_SID="ctxwatch-$$-1"
T1_PCT="/tmp/claude-context-${T1_SID}.pct"
T1_FLAG="/tmp/claude-context-watch-${T1_SID}.fired"
rm -f "$T1_PCT" "$T1_FLAG"
echo "59" >"$T1_PCT"

T1_RESULT=$(make_input "$T1_SID" | bash "$HOOK" 2>/dev/null)
rm -f "$T1_PCT" "$T1_FLAG"
assert_empty "T1: 59% emits nothing" "$T1_RESULT"

# ---- T2: at 60% emits the directive once ------------------------------------

echo
echo "--- T2: at 60% emits a directive exactly once"

T2_SID="ctxwatch-$$-2"
T2_PCT="/tmp/claude-context-${T2_SID}.pct"
T2_FLAG="/tmp/claude-context-watch-${T2_SID}.fired"
rm -f "$T2_PCT" "$T2_FLAG"
echo "60" >"$T2_PCT"

T2_RESULT1=$(make_input "$T2_SID" | bash "$HOOK" 2>/dev/null)
T2_CTX=$(printf '%s' "$T2_RESULT1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "T2a: directive mentions /compact" "$T2_CTX" "/compact"

T2_RESULT2=$(make_input "$T2_SID" | bash "$HOOK" 2>/dev/null)
rm -f "$T2_PCT" "$T2_FLAG"
assert_empty "T2b: second call in same session emits nothing (one-shot)" "$T2_RESULT2"

# ---- T3: above 60% also emits ------------------------------------------------

echo
echo "--- T3: 75% emits a directive"

T3_SID="ctxwatch-$$-3"
T3_PCT="/tmp/claude-context-${T3_SID}.pct"
T3_FLAG="/tmp/claude-context-watch-${T3_SID}.fired"
rm -f "$T3_PCT" "$T3_FLAG"
echo "75" >"$T3_PCT"

T3_RESULT=$(make_input "$T3_SID" | bash "$HOOK" 2>/dev/null)
rm -f "$T3_PCT" "$T3_FLAG"
T3_CTX=$(printf '%s' "$T3_RESULT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "T3: 75% emits a directive" "$T3_CTX" "/compact"

# ---- T4: pressure - missing pct file is silent ------------------------------

echo
echo "--- T4: pressure - missing pct file emits nothing"

T4_SID="ctxwatch-$$-4"
rm -f "/tmp/claude-context-${T4_SID}.pct" "/tmp/claude-context-watch-${T4_SID}.fired"

T4_RESULT=$(make_input "$T4_SID" | bash "$HOOK" 2>/dev/null)
assert_empty "T4: no pct file emits nothing" "$T4_RESULT"

# ---- T5: pressure - non-numeric pct file is silent --------------------------

echo
echo "--- T5: pressure - corrupt pct file emits nothing"

T5_SID="ctxwatch-$$-5"
T5_PCT="/tmp/claude-context-${T5_SID}.pct"
rm -f "$T5_PCT" "/tmp/claude-context-watch-${T5_SID}.fired"
echo "not-a-number" >"$T5_PCT"

T5_RESULT=$(make_input "$T5_SID" | bash "$HOOK" 2>/dev/null)
rm -f "$T5_PCT"
assert_empty "T5: corrupt pct value emits nothing" "$T5_RESULT"

# ---- Summary ----------------------------------------------------------------

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
