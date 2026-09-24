#!/usr/bin/env bash
# context-watch.sh, PostToolUse hook: direct a checkpoint-and-compact at 55%
# context usage, five points ahead of the harness's own 60% auto-compact.
#
# No hook event receives context-usage metrics directly (only the statusline
# does); statusline-command.sh bridges its exact context_window.used_percentage
# into a per-session /tmp file, this hook reads it. shared.bash sets
# CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60, so the harness's own auto-compact fires
# at 60% with no checkpoint of its own; this hook fires first, at 55%, so the
# model reliably gets a chance to wrap up the current step and write a
# one-sentence checkpoint before the harness's backstop compacts on its own,
# no manual /compact required. The 5-point gap is deliberate: it removes the
# race between the two mechanisms by construction instead of leaving them to
# compete at an identical threshold.
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
[ "$PCT" -ge 55 ] || exit 0

FLAG="/tmp/claude-context-watch-${SESSION_ID}.fired"
[ -f "$FLAG" ] && exit 0
touch "$FLAG" 2>/dev/null || exit 0

DIRECTIVE="## Context threshold reached (${PCT}%)

Context usage has reached ${PCT}%, at or above the 55% checkpoint threshold (rules/session.md). The harness's own auto-compact fires automatically at 60% with no checkpoint of its own, so finish the current step and state a one-sentence checkpoint of what is done and what remains now, then continue working. The automatic backstop will compact on its own; no manual \`/compact\` is needed."

jq -n --arg ctx "$DIRECTIVE" --arg msg "context ${PCT}% -- checkpoint, auto-compact will follow" \
	'{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}, "systemMessage": $msg}'

exit 0
