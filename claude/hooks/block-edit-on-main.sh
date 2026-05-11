#!/usr/bin/env bash
# PreToolUse hook: block Edit/Write on main or master.
# Registered in claude/settings.json under PreToolUse matcher "Write|Edit|MultiEdit|NotebookEdit".

BRANCH=$(git branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
	FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
	echo "[block-edit-on-main] BLOCKED: refusing to edit '${FILE}' on branch '${BRANCH}'." >&2
	echo "Create a branch first: git checkout -b claude/<topic>" >&2
	exit 2
fi

exit 0
