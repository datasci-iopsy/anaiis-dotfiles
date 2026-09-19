#!/usr/bin/env bash
# context-watch.sh, PostToolUse hook: direct a checkpoint-and-compact at 60%
# context usage.
#
# No hook event receives context-usage metrics directly (only the statusline
# does); statusline-command.sh bridges its exact context_window.used_percentage
# into a per-session /tmp file, this hook reads it. shared.bash sets
# CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60, so the harness's own auto-compact now
# fires at 60% directly; this hook's one-shot directive is a checkpoint
# nudge layered on top so the model wraps up the current step before
# compaction happens, not the sole enforcement mechanism it was before that
# env var existed. Ordering between the two at the same threshold is
# unverified.
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

Context usage has reached ${PCT}%, at or above the 60% compaction policy threshold (rules/session.md). The harness's own auto-compact is also configured to fire at this threshold, so finish the current step and state a one-sentence checkpoint of what is done and what remains now, then request \`/compact\` yourself rather than waiting to find out whether the harness beats you to it."

jq -n --arg ctx "$DIRECTIVE" --arg msg "context ${PCT}% -- checkpoint and /compact recommended" \
	'{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}, "systemMessage": $msg}'

exit 0
