#!/usr/bin/env bash
# usage-report.sh, read-only Claude Code usage report over a date range.
#
# Usage: usage-report.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--json]
# Defaults: --since 30 days ago, --until today.
#
# Reads ~/.claude/projects/**/*.jsonl (excludes subagent transcripts) and reports:
#   sessions count, token totals (input/output/cache_creation/cache_read),
#   agent spawn counts by subagent_type, top 5 sessions by total tokens,
#   cost-guard block count from ~/.claude/logs/cost-guard-blocks.log.
#
# --json  Raw integers in JSON; suitable for jq pipelines and Claude audits.
#         Default output uses comma-formatted numbers for human reading.

set -euo pipefail

SINCE="$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)"
UNTIL="$(date +%Y-%m-%d)"
JSON=0

while [ $# -gt 0 ]; do
	case "$1" in
		--since)
			SINCE="$2"
			shift 2
			;;
		--until)
			UNTIL="$2"
			shift 2
			;;
		--json)
			JSON=1
			shift
			;;
		-h | --help)
			sed -n '2,12p' "$0"
			exit 0
			;;
		*)
			echo "unknown arg: $1" >&2
			exit 64
			;;
	esac
done

if ! command -v jq &>/dev/null; then
	echo "jq required, install: brew install jq" >&2
	exit 1
fi

PROJECTS="$HOME/.claude/projects"
if [ ! -d "$PROJECTS" ]; then
	echo "no transcripts at $PROJECTS" >&2
	exit 1
fi

# Convert YYYY-MM-DD to epoch seconds (start of day local time)
to_epoch() {
	date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null \
		|| date -d "$1" +%s
}
SINCE_EPOCH=$(to_epoch "$SINCE")
UNTIL_EPOCH=$(($(to_epoch "$UNTIL") + 86400))

# Collect matching jsonl files by mtime in window
FILES=()
while IFS= read -r f; do
	mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")
	if [ "$mt" -ge "$SINCE_EPOCH" ] && [ "$mt" -lt "$UNTIL_EPOCH" ]; then
		FILES+=("$f")
	fi
done < <(find "$PROJECTS" -name '*.jsonl' -not -path '*/subagents/*' -not -empty)

SESSION_COUNT="${#FILES[@]}"

if [ "$SESSION_COUNT" -eq 0 ]; then
	if [ "$JSON" -eq 1 ]; then
		echo '{"since":"'"$SINCE"'","until":"'"$UNTIL"'","sessions":0}'
	else
		echo "Claude usage report: $SINCE to $UNTIL"
		echo "Sessions in window: 0"
		echo "(no sessions)"
	fi
	exit 0
fi

# Token totals
TOKENS=$(jq -s '
	[.[] | select(.type == "assistant") | .message.usage // {}]
	| {
		input: (map(.input_tokens // 0) | add),
		output: (map(.output_tokens // 0) | add),
		cache_creation: (map(.cache_creation_input_tokens // 0) | add),
		cache_read: (map(.cache_read_input_tokens // 0) | add)
	}
	| . + {total: (.input + .output + .cache_creation + .cache_read)}
' "${FILES[@]}")

# Agent spawn counts: produce JSON object {type: count, ...}
SPAWNS_RAW=$(for f in "${FILES[@]}"; do
	jq -r '
		select(.type == "assistant")
		| (.message.content // .content // [])[]
		| select(.type == "tool_use" and .name == "Agent")
		| .input.subagent_type // "general-purpose"
	' "$f" 2>/dev/null
done | sort | uniq -c | sort -rn)

SPAWNS_JSON=$(echo "$SPAWNS_RAW" | awk 'BEGIN{print "{"} NR>1{print ","} {gsub(/^ +/,""); n=$1; $1=""; sub(/^ /,""); printf "  \"%s\": %d", $0, n} END{print "\n}"}')

# Top 5 sessions by total tokens: JSON array
TOP5_JSON=$(for f in "${FILES[@]}"; do
	tot=$(jq -s '
		[.[] | select(.type == "assistant") | .message.usage // {}
			| (.input_tokens // 0) + (.output_tokens // 0)
			+ (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
		] | add // 0
	' "$f")
	printf '%s\t%s\n' "$tot" "$(basename "$f" .jsonl)"
done | sort -rn | head -5 | awk 'BEGIN{print "["} NR>1{print ","} {printf "  {\"session\":\"%s\",\"tokens\":%d}", $2, $1} END{print "\n]"}')

# Cost-guard blocks
BLOCK_LOG="$HOME/.claude/logs/cost-guard-blocks.log"
BLOCKS=0
if [ -f "$BLOCK_LOG" ]; then
	BLOCKS=$(awk -F'\t' -v s="$SINCE" -v u="$UNTIL" '
		{ d = substr($1, 1, 10); if (d >= s && d <= u) n++ }
		END { print n + 0 }
	' "$BLOCK_LOG")
fi

# --- Output ---

if [ "$JSON" -eq 1 ]; then
	jq -n \
		--arg since "$SINCE" \
		--arg until "$UNTIL" \
		--argjson sessions "$SESSION_COUNT" \
		--argjson tokens "$TOKENS" \
		--argjson spawns "$SPAWNS_JSON" \
		--argjson top5 "$TOP5_JSON" \
		--argjson blocks "$BLOCKS" \
		'{since:$since, until:$until, sessions:$sessions, tokens:$tokens, agent_spawns:$spawns, top5_by_tokens:$top5, cost_guard_blocks:$blocks}'
	exit 0
fi

# Human-readable: comma-formatted numbers
fmt() { printf "%'.0f" "$1"; }

echo "Claude usage report: $SINCE to $UNTIL"
echo "Sessions in window: $SESSION_COUNT"
echo

echo "Token totals:"
echo "$TOKENS" | jq -r '
	"  input          : \(.input)",
	"  output         : \(.output)",
	"  cache_creation : \(.cache_creation)",
	"  cache_read     : \(.cache_read)",
	"  total          : \(.total)"
' | while IFS= read -r line; do
	label="${line%%:*}:"
	raw="${line##*: }"
	printf "  %-17s %s\n" "${label#  }" "$(fmt "$raw")"
done
echo

echo "Agent spawns by type:"
echo "$SPAWNS_RAW" | awk '{printf "  %-22s %s\n", $2, $1}'
echo

echo "Top 5 sessions by total tokens:"
echo "$TOP5_JSON" | jq -r '.[] | "\(.tokens)\t\(.session)"' \
	| while IFS=$'\t' read -r tok sid; do
		printf "  %15s  %s\n" "$(fmt "$tok")" "$sid"
	done
echo

echo "Cost-guard blocks:"
if [ -f "$BLOCK_LOG" ]; then
	echo "  $(fmt "$BLOCKS") block(s) in window (log: $BLOCK_LOG)"
else
	echo "  no log yet ($BLOCK_LOG)"
fi
