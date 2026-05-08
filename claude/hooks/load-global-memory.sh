#!/usr/bin/env bash
# load-global-memory.sh, emit the cross-project memory tier as context
# on the FIRST UserPromptSubmit of each Claude session.
#
# Tracks first-prompt-ness via a marker file at /tmp/claude-session-<id>.global-loaded
# so subsequent prompts in the same session don't re-emit the global tier.
# Skips silently if the global tier is absent.
#
# Output:
#   First prompt: JSON systemMessage with the contents of ~/.claude/memory/MEMORY.md
#                 plus all topical files referenced from it.
#   Subsequent:   nothing (exit 0).
# Exit 0 always, never block.

set -eu

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
	exit 0
fi

GLOBAL_DIR="$HOME/.claude/memory"
INDEX="$GLOBAL_DIR/MEMORY.md"

[ -f "$INDEX" ] || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0
# Reject SESSION_IDs with path-unsafe chars to prevent marker path traversal.
printf '%s' "$SESSION_ID" | grep -qE '^[a-zA-Z0-9._-]+$' || exit 0

MARKER="/tmp/claude-session-${SESSION_ID}.global-loaded"

# If we've already loaded for this session, do nothing.
[ -f "$MARKER" ] && exit 0

# Drop a marker so subsequent prompts in this session skip.
touch "$MARKER" 2>/dev/null || exit 0

# Build the context payload: the index plus every topical file it references.
# We read the index verbatim and concatenate referenced files in order.
PAYLOAD="## Global memory (cross-project, user-level)

Restored once per session from \`~/.claude/memory/\`. These are user-level facts and preferences that apply across every project on this machine.

### Index

$(cat "$INDEX")

"

# Pull in any markdown link targets from the index, e.g. [Title](filename.md)
while IFS= read -r f; do
	target="$GLOBAL_DIR/$f"
	# Guard against path traversal: target must resolve under GLOBAL_DIR.
	case "$target" in "$GLOBAL_DIR/"*) ;; *) continue ;; esac
	if [ -f "$target" ] && [ "$f" != "MEMORY.md" ]; then
		PAYLOAD="$PAYLOAD
### $f

$(cat "$target")
"
	fi
done < <(grep -oE '\([a-zA-Z0-9_.]+\.md\)' "$INDEX" | tr -d '()' | sort -u)

# Emit as a systemMessage so Claude has the content as context for this turn.
jq -n --arg msg "$PAYLOAD" '{"systemMessage": $msg}'

exit 0
