#!/usr/bin/env bash
# memory-quality-check.sh -- monthly memory quality advisory
#
# Fires on UserPromptSubmit once per session (marker file guard) and once per
# month (stamp file guard). Scans global memory files for staleness (>90 days
# since last modification) and emits a systemMessage so Claude can assess
# relevance and surface candidates to the user for review or removal.
#
# Age is the objective signal; Claude provides the relevance judgment.
# Exit 0 always; never blocks UserPromptSubmit.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
	exit 0
fi

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0
printf '%s' "$SESSION_ID" | grep -qE '^[a-zA-Z0-9._-]+$' || exit 0

MARKER="/tmp/claude-session-${SESSION_ID}.memory-quality-checked"
[ -f "$MARKER" ] && exit 0
touch "$MARKER" 2>/dev/null || exit 0

STATE_DIR="$HOME/.claude"
MEMORY_DIR="$STATE_DIR/memory"
STAMP="$STATE_DIR/.maintenance-memory-quality"
TODAY=$(date +%Y-%m-%d)

ymd_to_epoch() {
	if [[ "$OSTYPE" == darwin* ]]; then
		date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" +%s 2>/dev/null || echo 0
	else
		date -d "$1 00:00:00" +%s 2>/dev/null || echo 0
	fi
}

TODAY_SEC=$(ymd_to_epoch "$TODAY")
last=$(cat "$STAMP" 2>/dev/null || echo "1970-01-01")
last_sec=$(ymd_to_epoch "$last")
days_since=$(((TODAY_SEC - last_sec) / 86400))

[ "$days_since" -ge 30 ] || exit 0
echo "$TODAY" >"$STAMP"

[ -d "$MEMORY_DIR" ] || exit 0

STALE=""
NOW_SEC=$(date +%s)

while IFS= read -r f; do
	base=$(basename "$f")
	[ "$base" = "MEMORY.md" ] && continue

	if [[ "$OSTYPE" == darwin* ]]; then
		mtime=$(stat -f %m "$f" 2>/dev/null || echo 0)
	else
		mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
	fi

	age_days=$(((NOW_SEC - mtime) / 86400))

	if [ "$age_days" -gt 90 ]; then
		STALE="${STALE}- \`${base}\` (${age_days} days since last modified)
"
	fi
done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)

[ -n "$STALE" ] || exit 0

PAYLOAD="## Memory quality advisory (monthly)

The following global memory files have not been modified in over 90 days. During this session, evaluate whether each still reflects how the user works. Surface any that seem stale, inaccurate, or no longer applicable -- with a one-sentence summary of the concern -- and ask the user whether to update or remove it. Only raise this if you have a genuine signal; do not mention it if the content still looks current.

${STALE}"

jq -n --arg msg "$PAYLOAD" '{"systemMessage": $msg}'
exit 0
