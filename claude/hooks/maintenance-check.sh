#!/usr/bin/env bash
# maintenance-check.sh -- periodic maintenance reminders at session start
#
# Triggered by UserPromptSubmit hook. Checks metrics against thresholds and
# prints a one-line reminder to stderr when action is needed. Non-blocking
# (always exits 0). Cadence controlled by stamp files to avoid nagging.
#
# Checks:
#   Plans  , weekly:  notify if >10 files or any older than 14 days
#   Sessions, monthly: notify if ~/.claude/projects exceeds 50 MB

set -euo pipefail

STATE_DIR="$HOME/.claude"
PLAN_DIR="$STATE_DIR/plans"
TODAY=$(date +%Y-%m-%d)

# Portable YYYY-MM-DD -> epoch at midnight local time.
# Both branches anchor to 00:00:00 to keep results deterministic across
# BSD/GNU and across times of day.
ymd_to_epoch() {
	if [[ "$OSTYPE" == darwin* ]]; then
		date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" +%s 2>/dev/null || echo 0
	else
		date -d "$1 00:00:00" +%s 2>/dev/null || echo 0
	fi
}

TODAY_SEC=$(ymd_to_epoch "$TODAY")

stamp_days_ago() {
	local stamp_file="$1"
	local last
	last=$(cat "$stamp_file" 2>/dev/null || echo "1970-01-01")
	local last_sec
	last_sec=$(ymd_to_epoch "$last")
	echo $(((TODAY_SEC - last_sec) / 86400))
}

# --- Plan files (weekly) ---
PLAN_STAMP="$STATE_DIR/.maintenance-plans"
if [ "$(stamp_days_ago "$PLAN_STAMP")" -ge 7 ]; then
	count=$(find "$PLAN_DIR" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
	old=$(find "$PLAN_DIR" -name "*.md" -mtime +14 2>/dev/null | wc -l | tr -d ' ')
	if [ "$count" -gt 10 ] || [ "$old" -gt 0 ]; then
		echo "[maintenance] Plans: ${count} files, ${old} older than 14 days -- bash ~/.claude/clean-plans.sh" >&2
	fi
	echo "$TODAY" >"$PLAN_STAMP"
fi

# --- Session files (monthly) ---
SESSION_STAMP="$STATE_DIR/.maintenance-sessions"
if [ "$(stamp_days_ago "$SESSION_STAMP")" -ge 30 ]; then
	session_mb=$(du -sm "$STATE_DIR/projects" 2>/dev/null | cut -f1 || echo 0)
	if [ "${session_mb:-0}" -gt 50 ]; then
		echo "[maintenance] Sessions: ${session_mb}MB -- claude-cleanup --older-than 30" >&2
	fi
	echo "$TODAY" >"$SESSION_STAMP"
fi

# --- Repo hooks (weekly) ---
HOOKS_STAMP="$STATE_DIR/.maintenance-hooks"
if [ "$(stamp_days_ago "$HOOKS_STAMP")" -ge 7 ]; then
	need_fix=$(bash "$HOME/.claude/scripts/audit-repo-hooks.sh" 2>/dev/null \
		| grep -cE '^\s*(STALE|missing|absent)' || true)
	if [ "${need_fix:-0}" -gt 0 ]; then
		echo "[maintenance] Repo hooks: ${need_fix} repos need attention -- bash ~/.claude/scripts/audit-repo-hooks.sh" >&2
	fi
	echo "$TODAY" >"$HOOKS_STAMP"
fi

exit 0
