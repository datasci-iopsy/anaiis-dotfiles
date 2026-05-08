#!/bin/bash
# post-compact.sh, re-inject session context after compaction completes
#
# Reads the most recent handoff file written by pre-compact.sh and outputs
# it as a systemMessage so Claude has immediate context in the compacted
# session without needing to re-read files or re-explore prior state.
#
# Output: JSON { "systemMessage": "..." } to stdout, or nothing if no handoff.
# Exit 0 always.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
	exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

if [ -z "$CWD" ]; then
	exit 0
fi

PROJECT_KEY=$(echo "$CWD" | tr '/.' '-')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"
HANDOFFS_DIR="$MEMORY_DIR/handoffs"

# Find the most recent handoff: prefer the handoffs/ subdirectory introduced
# in Phase 9, fall back to the flat layout for projects that have not yet
# been touched by an updated pre-compact.
LATEST_HANDOFF=$(ls -t "$HANDOFFS_DIR"/handoff_*.md 2>/dev/null | head -1 || echo "")
if [ -z "$LATEST_HANDOFF" ]; then
	LATEST_HANDOFF=$(ls -t "$MEMORY_DIR"/handoff_*.md 2>/dev/null | head -1 || echo "")
fi

if [ -z "$LATEST_HANDOFF" ] || [ ! -f "$LATEST_HANDOFF" ]; then
	exit 0
fi

HANDOFF_CONTENT=$(cat "$LATEST_HANDOFF")

# Output systemMessage, injected into the compacted context so Claude
# immediately knows what was in scope before compaction.
jq -n --arg content "$HANDOFF_CONTENT" \
	'{"systemMessage": ("## Restored from pre-compact handoff\n\nThe following context was captured immediately before compaction. Use it to avoid re-reading files and to restore task continuity.\n\n" + $content)}'

exit 0
