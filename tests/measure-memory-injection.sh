#!/usr/bin/env bash
# tests/measure-memory-injection.sh -- measure per-session-start injection
# cost of session-start-context.sh against the live global + project tiers.
#
# Usage: bash tests/measure-memory-injection.sh [--report]
#   --report   write reports/memory-cost-baseline.md after measurement
#
# Behavioral coverage (emission channel, idempotency, pressure cases) lives in
# tests/test-session-start-context.sh; this script measures cost only.
#
# Exit 0 always; the threshold result is printed but does not affect exit code.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOME/.claude/hooks/session-start-context.sh"

WRITE_REPORT=0
[ "${1:-}" = "--report" ] && WRITE_REPORT=1

if [ ! -f "$HOOK" ]; then
	echo "  SKIP  hook not found at $HOOK (symlinks not installed?)"
	exit 0
fi

echo
echo "--- Measurement: actual injection cost (live files)"

MEAS_SID="measure-$$-$(date +%s)"
MEAS_INPUT=$(jq -n --arg sid "$MEAS_SID" --arg cwd "$(pwd)" \
	'{"source": "startup", "session_id": $sid, "cwd": $cwd, "hook_event_name": "SessionStart"}')

RESULT=$(printf '%s' "$MEAS_INPUT" | bash "$HOOK" 2>/dev/null) || RESULT=""

if [ -n "$RESULT" ]; then
	GLOBAL_MSG=$(printf '%s' "$RESULT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
else
	GLOBAL_MSG=""
fi

GLOBAL_BYTES=$(printf '%s' "$GLOBAL_MSG" | wc -c | tr -d ' ')
GLOBAL_TOKENS=$((GLOBAL_BYTES * 10 / 35))

# Startup-time cost: the harness auto-loads only the project MEMORY.md index;
# topical project files are read on demand and are not part of session-start
# cost (measuring them here previously overcounted and mis-triggered an
# escalation gate, see tmp/memory-system-review-2026-07-15.md gap G6).
PROJECT_KEY=$(pwd | tr '/.' '-')
PROJECT_MEMORY_DIR="$HOME/.claude/projects/${PROJECT_KEY}/memory"
PROJECT_BYTES=0
if [ -f "$PROJECT_MEMORY_DIR/MEMORY.md" ]; then
	PROJECT_BYTES=$(wc -c <"$PROJECT_MEMORY_DIR/MEMORY.md" | tr -d ' ')
fi
PROJECT_TOKENS=$((PROJECT_BYTES * 10 / 35))

TOTAL_TOKENS=$((GLOBAL_TOKENS + PROJECT_TOKENS))
THRESHOLD=5000

echo
printf '  %-34s %8d bytes  ~%d tokens\n' \
	"Global tier (SessionStart-injected):" "$GLOBAL_BYTES" "$GLOBAL_TOKENS"
printf '  %-34s %8d bytes  ~%d tokens\n' \
	"Project tier (harness-native index):" "$PROJECT_BYTES" "$PROJECT_TOKENS"
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
| Global (SessionStart-injected) | $GLOBAL_BYTES | $GLOBAL_TOKENS |
| Project (harness-native index) | $PROJECT_BYTES | $PROJECT_TOKENS |
| **Total** | $((GLOBAL_BYTES + PROJECT_BYTES)) | **$TOTAL_TOKENS** |

Token estimate: characters / 3.5 (English markdown rule of thumb).

## Decision gate

Threshold: $THRESHOLD tokens

**$DECISION**
EOF
	echo "  Report written: $REPORT"
fi

exit 0
