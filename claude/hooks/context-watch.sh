#!/usr/bin/env bash
# context-watch.sh, PostToolUse hook: direct a checkpoint-and-compact at 60%
# context usage.
#
# No hook event receives context-usage metrics directly (only the statusline
# does); statusline-command.sh bridges its exact context_window.used_percentage
# into a per-session /tmp file, this hook reads it. CC 2.1.207 has no
# configurable auto-compact threshold and no programmatic way to trigger
# compaction (only the ~85% harness default and manual /compact), so 60% is
# enforced as a one-shot directive asking the model to checkpoint and request
# /compact itself, rather than a fully automatic trigger.
#
# Fires at most once per session (flag file guard). Silent when the pct file
# is absent, unreadable, or below threshold.
#
# Output: JSON { "hookSpecificOutput": { "hookEventName": "PostToolUse",
#   "additionalContext": "..." }, "systemMessage": "..." }
# Exit 0 always, never blocks the tool call.

set -eu

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
[ -n "$SESSION_ID" ] || exit 0
printf '%s' "$SESSION_ID" | grep -qE '^[a-zA-Z0-9._-]+$' || exit 0

PCT_FILE="/tmp/claude-context-${SESSION_ID}.pct"
[ -f "$PCT_FILE" ] || exit 0

PCT=$(cat "$PCT_FILE" 2>/dev/null || echo "")
printf '%s' "$PCT" | grep -qE '^[0-9]+$' || exit 0
[ "$PCT" -ge 60 ] || exit 0

FLAG="/tmp/claude-context-watch-${SESSION_ID}.fired"
[ -f "$FLAG" ] && exit 0
touch "$FLAG" 2>/dev/null || exit 0

DIRECTIVE="## Context threshold reached (${PCT}%)

Context usage has reached ${PCT}%, at or above the 60% compaction policy threshold (rules/session.md). No automatic compaction fires until the harness's own ~85% backstop, so finish the current step, state a one-sentence checkpoint of what is done and what remains, then request \`/compact\` now rather than continuing toward that backstop."

jq -n --arg ctx "$DIRECTIVE" --arg msg "context ${PCT}% -- checkpoint and /compact recommended" \
	'{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}, "systemMessage": $msg}'

exit 0
