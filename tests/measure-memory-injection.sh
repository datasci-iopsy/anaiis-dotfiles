#!/usr/bin/env bash
# tests/measure-memory-injection.sh  --  measure per-session injection cost
# of load-global-memory.sh AND verify its guard behaviors.
#
# Usage: bash tests/measure-memory-injection.sh [--report]
#   --report   write reports/memory-cost-baseline.md after measurement
#
# Exit 0 if all behavioral tests pass; non-zero on any failure.
# Measurement threshold result is printed but does NOT affect exit code.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOME/.claude/hooks/load-global-memory.sh"

PASS=0
FAIL=0
WRITE_REPORT=0
[ "${1:-}" = "--report" ] && WRITE_REPORT=1

pass() {
	echo "  PASS  $1"
	PASS=$((PASS + 1))
}

fail() {
	echo "  FAIL  $1"
	FAIL=$((FAIL + 1))
}

assert_json_field() {
	local label="$1" json="$2" field="$3"
	printf '%s' "$json" | jq -e ".$field" >/dev/null 2>&1 \
		&& pass "$label" \
		|| fail "$label (missing field: $field)"
}

assert_empty() {
	local label="$1" value="$2"
	[ -z "$value" ] \
		&& pass "$label" \
		|| fail "$label (expected empty, got: ${value:0:80})"
}

make_input() {
	local sid="$1"
	jq -n --arg sid "$sid" '{
        "session_id": $sid,
        "hook_event_name": "UserPromptSubmit",
        "prompt": "test prompt for injection measurement"
    }'
}

if [ ! -f "$HOOK" ]; then
	echo "  SKIP  hook not found at $HOOK (symlinks not installed?)"
	exit 0
fi

# ---- T1: smoke - valid systemMessage emission -------------------------------

echo
echo "--- T1: smoke - valid systemMessage emission"

T1_HOME=$(mktemp -d)
T1_SID="smoketest-$$-$(date +%s)"
T1_MARKER="/tmp/claude-session-${T1_SID}.global-loaded"
rm -f "$T1_MARKER"

mkdir -p "$T1_HOME/.claude/memory"
cat >"$T1_HOME/.claude/memory/MEMORY.md" <<'MEMEOF'
# Global Memory Index

- [User profile](user_profile.md): test user facts
MEMEOF
cat >"$T1_HOME/.claude/memory/user_profile.md" <<'PROFEOF'
---
name: user-profile
description: test user facts
type: user
---

Test user, senior engineer.
PROFEOF

T1_RESULT=$(make_input "$T1_SID" | HOME="$T1_HOME" bash "$HOOK" 2>/dev/null)
rm -f "$T1_MARKER"
rm -rf "$T1_HOME"

if [ -n "$T1_RESULT" ]; then
	assert_json_field "T1: emits .systemMessage" "$T1_RESULT" "systemMessage"
else
	fail "T1: hook emitted nothing on first call"
fi

# ---- T2: idempotency - second call is silent --------------------------------

echo
echo "--- T2: idempotency - second call is silent"

T2_HOME=$(mktemp -d)
T2_SID="idemptest-$$-$(date +%s)"
T2_MARKER="/tmp/claude-session-${T2_SID}.global-loaded"
rm -f "$T2_MARKER"

mkdir -p "$T2_HOME/.claude/memory"
echo "# Global Memory Index" >"$T2_HOME/.claude/memory/MEMORY.md"

T2_RESULT1=$(make_input "$T2_SID" | HOME="$T2_HOME" bash "$HOOK" 2>/dev/null)
T2_RESULT2=$(make_input "$T2_SID" | HOME="$T2_HOME" bash "$HOOK" 2>/dev/null)

rm -f "$T2_MARKER"
rm -rf "$T2_HOME"

if [ -n "$T2_RESULT1" ]; then
	pass "T2a: first call emits"
else
	fail "T2a: first call was unexpectedly silent"
fi
assert_empty "T2b: second call is silent (marker guard)" "$T2_RESULT2"

# ---- T3: pressure - missing MEMORY.md exits 0 silently ---------------------

echo
echo "--- T3: pressure - missing MEMORY.md exits 0 silently"

T3_HOME=$(mktemp -d)
T3_SID="missingtest-$$-$(date +%s)"
T3_MARKER="/tmp/claude-session-${T3_SID}.global-loaded"
rm -f "$T3_MARKER"

mkdir -p "$T3_HOME/.claude"

T3_RESULT=$(make_input "$T3_SID" | HOME="$T3_HOME" bash "$HOOK" 2>/dev/null)

rm -f "$T3_MARKER"
rm -rf "$T3_HOME"

assert_empty "T3: no output when MEMORY.md absent" "$T3_RESULT"

# ---- T4: pressure - path-unsafe session_id rejected ------------------------

echo
echo "--- T4: pressure - path-unsafe session_id rejected"

T4_HOME=$(mktemp -d)
mkdir -p "$T4_HOME/.claude/memory"
echo "# Global Memory Index" >"$T4_HOME/.claude/memory/MEMORY.md"

T4_RESULT=$(printf '%s' \
	'{"session_id": "../evil/path", "hook_event_name": "UserPromptSubmit", "prompt": "x"}' \
	| HOME="$T4_HOME" bash "$HOOK" 2>/dev/null)

rm -rf "$T4_HOME"
assert_empty "T4: no output for path-unsafe session_id" "$T4_RESULT"

# ---- T5: pressure - missing jq exits 0 silently ----------------------------

echo
echo "--- T5: pressure - missing jq exits 0 silently"

T5_HOME=$(mktemp -d)
T5_SID="jqtest-$$-$(date +%s)"
T5_MARKER="/tmp/claude-session-${T5_SID}.global-loaded"
rm -f "$T5_MARKER"

mkdir -p "$T5_HOME/.claude/memory"
echo "# Global Memory Index" >"$T5_HOME/.claude/memory/MEMORY.md"

# Use a minimal PATH (/bin only) that has cat but no jq.
# jq is in /opt/homebrew/bin and /usr/bin on this machine; neither is /bin.
# The hook only needs cat before its jq guard fires and exits 0.
T5_RESULT=$(make_input "$T5_SID" \
	| HOME="$T5_HOME" PATH="/bin" bash "$HOOK" 2>/dev/null) || true

rm -f "$T5_MARKER"
rm -rf "$T5_HOME"

assert_empty "T5: no output when jq absent from PATH" "$T5_RESULT"

# ---- Measurement: actual injection cost against live memory files -----------

echo
echo "--- Measurement: actual injection cost (live files)"

MEAS_SID="measure-$$-$(date +%s)"
MEAS_MARKER="/tmp/claude-session-${MEAS_SID}.global-loaded"
rm -f "$MEAS_MARKER"

GLOBAL_PAYLOAD=$(make_input "$MEAS_SID" | bash "$HOOK" 2>/dev/null) || GLOBAL_PAYLOAD=""
rm -f "$MEAS_MARKER"

if [ -n "$GLOBAL_PAYLOAD" ]; then
	GLOBAL_MSG=$(printf '%s' "$GLOBAL_PAYLOAD" | jq -r '.systemMessage // ""' 2>/dev/null)
else
	GLOBAL_MSG=""
fi

GLOBAL_BYTES=$(printf '%s' "$GLOBAL_MSG" | wc -c | tr -d ' ')
GLOBAL_TOKENS=$((GLOBAL_BYTES * 10 / 35))

PROJECT_KEY=$(echo "$(pwd)" | tr '/.' '-')
PROJECT_MEMORY_DIR="$HOME/.claude/projects/${PROJECT_KEY}/memory"
PROJECT_BYTES=0

if [ -f "$PROJECT_MEMORY_DIR/MEMORY.md" ]; then
	IDX_SIZE=$(wc -c <"$PROJECT_MEMORY_DIR/MEMORY.md" | tr -d ' ')
	PROJECT_BYTES=$((PROJECT_BYTES + IDX_SIZE))
	while IFS= read -r linked_file; do
		LINKED="$PROJECT_MEMORY_DIR/$linked_file"
		[ -f "$LINKED" ] || continue
		F_SIZE=$(wc -c <"$LINKED" | tr -d ' ')
		PROJECT_BYTES=$((PROJECT_BYTES + F_SIZE))
	done < <(grep -oE '\([a-zA-Z0-9_.]+\.md\)' "$PROJECT_MEMORY_DIR/MEMORY.md" 2>/dev/null \
		| tr -d '()' | sort -u)
fi
PROJECT_TOKENS=$((PROJECT_BYTES * 10 / 35))

TOTAL_TOKENS=$((GLOBAL_TOKENS + PROJECT_TOKENS))
THRESHOLD=5000

echo
printf '  %-34s %8d bytes  ~%d tokens\n' \
	"Global tier (hook-injected):" "$GLOBAL_BYTES" "$GLOBAL_TOKENS"
printf '  %-34s %8d bytes  ~%d tokens\n' \
	"Project tier (harness-native):" "$PROJECT_BYTES" "$PROJECT_TOKENS"
echo "  -----------------------------------------------------------"
printf '  %-34s            ~%d tokens\n' "Total estimated:" "$TOTAL_TOKENS"
printf '  %-34s             %d tokens\n' "Threshold:" "$THRESHOLD"
echo

if [ "$TOTAL_TOKENS" -lt "$THRESHOLD" ]; then
	DECISION="WITHIN BUDGET: stop here. Current system is correctly sized."
else
	DECISION="THRESHOLD EXCEEDED: proceed to Phase C0 (mem0-cli viability check)."
fi

echo "  DECISION: $DECISION"

if [ "$WRITE_REPORT" -eq 1 ]; then
	REPORT="$REPO_DIR/reports/memory-cost-baseline.md"
	cat >"$REPORT" <<EOF
# Memory Injection Cost Baseline

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Machine: $(hostname)
Branch: $(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo "unknown")

## Measurements

| Tier | Bytes | Est. Tokens |
|---|---|---|
| Global (hook-injected) | $GLOBAL_BYTES | $GLOBAL_TOKENS |
| Project (harness-native) | $PROJECT_BYTES | $PROJECT_TOKENS |
| **Total** | $((GLOBAL_BYTES + PROJECT_BYTES)) | **$TOTAL_TOKENS** |

Token estimate: characters / 3.5 (English markdown rule of thumb).

## Decision gate

Threshold: $THRESHOLD tokens

**$DECISION**
EOF
	echo "  Report written: $REPORT"
fi

# ---- Summary ----------------------------------------------------------------

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

if [ "$FAIL" -gt 0 ]; then
	exit 1
fi
exit 0
