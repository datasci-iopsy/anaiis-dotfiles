#!/usr/bin/env bash
# tests/measure-userpromptsubmit.sh, measure each UserPromptSubmit hook
# in isolation, repeated N times, report median + sum.
#
# Usage: bash tests/measure-userpromptsubmit.sh [N]   # default N=5
#
# Feeds each hook the same synthetic JSON payload that Claude Code would
# pass at runtime, then times wall-clock with the shell's TIMEFORMAT
# directive at millisecond resolution.

set -eu

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="${1:-5}"

HOOKS=(
    "$REPO_DIR/claude/hooks/maintenance-check.sh"
    "$REPO_DIR/claude/hooks/coderabbit-triage.sh"
    "$REPO_DIR/claude/hooks/ensure-repo-hooks.sh"
)

# Synthetic UserPromptSubmit input, what Claude Code sends to hooks.
PAYLOAD=$(cat <<JSON
{
    "session_id": "measure-$RANDOM",
    "transcript_path": "/dev/null",
    "cwd": "$REPO_DIR",
    "hook_event_name": "UserPromptSubmit",
    "prompt": "test prompt for hook latency measurement"
}
JSON
)

# Median of an array of integers (ms)
median() {
    local sorted
    sorted=$(printf '%s\n' "$@" | sort -n)
    local count
    count=$(printf '%s\n' "$sorted" | wc -l | tr -d ' ')
    local mid=$((count / 2))
    if [ $((count % 2)) -eq 1 ]; then
        printf '%s\n' "$sorted" | sed -n "$((mid + 1))p"
    else
        local a b
        a=$(printf '%s\n' "$sorted" | sed -n "${mid}p")
        b=$(printf '%s\n' "$sorted" | sed -n "$((mid + 1))p")
        echo $(((a + b) / 2))
    fi
}

# Time a single hook invocation in ms (uses date +%s%N → ns → ms)
time_one() {
    local hook="$1"
    local start_ns end_ns
    if [[ "$OSTYPE" == darwin* ]]; then
        # BSD date does not support +%N. Use perl for sub-second precision.
        start_ns=$(perl -MTime::HiRes=time -e 'printf("%d\n", time()*1_000_000_000)')
        printf '%s' "$PAYLOAD" | bash "$hook" > /dev/null 2>&1 || true
        end_ns=$(perl -MTime::HiRes=time -e 'printf("%d\n", time()*1_000_000_000)')
    else
        start_ns=$(date +%s%N)
        printf '%s' "$PAYLOAD" | bash "$hook" > /dev/null 2>&1 || true
        end_ns=$(date +%s%N)
    fi
    echo $(((end_ns - start_ns) / 1000000))
}

echo "Measuring UserPromptSubmit hooks (n=$N runs each, in ms)"
echo "──────────────────────────────────────────────────────"
echo

TOTAL_MEDIAN=0
for hook in "${HOOKS[@]}"; do
    name=$(basename "$hook")
    times=()
    for _ in $(seq 1 "$N"); do
        times+=("$(time_one "$hook")")
    done
    med=$(median "${times[@]}")
    TOTAL_MEDIAN=$((TOTAL_MEDIAN + med))
    printf '  %-35s median=%4d ms   runs=[%s]\n' "$name" "$med" "$(IFS=,; echo "${times[*]}")"
done

echo
echo "──────────────────────────────────────────────────────"
echo "  Aggregate median: $TOTAL_MEDIAN ms"

THRESHOLD=100
if [ "$TOTAL_MEDIAN" -le "$THRESHOLD" ]; then
    echo "  Verdict: KEEP CHAIN, aggregate ≤ ${THRESHOLD} ms"
    exit 0
else
    echo "  Verdict: CONSOLIDATE, aggregate > ${THRESHOLD} ms"
    exit 1
fi
