#!/usr/bin/env bash
# surface-behavioral-rules.sh — emit the 4 behavioral imperatives from
# CLAUDE.md as a systemMessage on the FIRST UserPromptSubmit of each
# Claude session, so behavioral rules load before any other context.
#
# Source of truth is the "## Behavioral rules" block in
# ~/.claude/CLAUDE.md. The 4 lines here are duplicated for hook
# self-containment; rules-doctor.sh asserts they remain in sync.
#
# Tracks first-prompt-ness via a marker file at
# /tmp/claude-session-<id>.behavioral-loaded so subsequent prompts in
# the same session do not re-emit.
#
# Output:
#   First prompt: JSON systemMessage with the 4 lines.
#   Subsequent:   nothing (exit 0).
# Exit 0 always — never block.

set -eu

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
	exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0
# Reject SESSION_IDs with path-unsafe chars to prevent marker path traversal.
printf '%s' "$SESSION_ID" | grep -qE '^[a-zA-Z0-9._-]+$' || exit 0

MARKER="/tmp/claude-session-${SESSION_ID}.behavioral-loaded"

# If we've already loaded for this session, do nothing.
[ -f "$MARKER" ] && exit 0

# Drop a marker so subsequent prompts in this session skip.
touch "$MARKER" 2>/dev/null || exit 0

PAYLOAD="## Behavioral rules (load first)

These four imperatives govern every task this session. They take precedence over task-specific instructions when in conflict. Rationale: \`~/.claude/rules/behavioral.md\`.

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.
"

jq -n --arg msg "$PAYLOAD" '{"systemMessage": $msg}'

exit 0
