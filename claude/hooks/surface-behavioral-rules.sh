#!/usr/bin/env bash
# surface-behavioral-rules.sh, emit behavioral imperatives as a systemMessage
# on the first UserPromptSubmit of each session. Content is extracted from
# rules/behavioral.md so the hook stays in sync when that file changes.
#
# Exit 0 always (never blocks UserPromptSubmit). If extraction fails, the
# payload contains a warning instead of silently injecting nothing.

set -eu

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
	exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0
printf '%s' "$SESSION_ID" | grep -qE '^[a-zA-Z0-9._-]+$' || exit 0

MARKER="/tmp/claude-session-${SESSION_ID}.behavioral-loaded"
[ -f "$MARKER" ] && exit 0
touch "$MARKER" 2>/dev/null || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTOR="$SCRIPT_DIR/../scripts/extract-behavioral-rules.sh"

RULES=""
if [ -x "$EXTRACTOR" ]; then
	RULES=$(bash "$EXTRACTOR" 2>/dev/null || true)
fi

if [ -z "$RULES" ]; then
	PAYLOAD="## Behavioral rules (LOAD ERROR)

Warning: could not extract behavioral rules from rules/behavioral.md.
Check ~/.claude/scripts/extract-behavioral-rules.sh and the source file.
"
else
	PAYLOAD="## Behavioral rules (load first)

These imperatives govern every task this session. They take precedence over task-specific instructions when in conflict. Full rationale in \`~/.claude/rules/behavioral.md\`.

$RULES
"
fi

jq -n --arg msg "$PAYLOAD" '{"systemMessage": $msg}'

exit 0
