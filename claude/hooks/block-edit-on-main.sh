#!/usr/bin/env bash
# PreToolUse hook: block Edit/Write on main or master.
# Exempt: paths under $HOME/.claude/plans/ -- plan files may be written from main;
# implementation must run on a claude/<topic> branch (see rules/git.md).
# Registered in claude/settings.json under PreToolUse matcher "Write|Edit|MultiEdit|NotebookEdit".

BRANCH=$(git branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
	FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)

	# Resolve via python3 to handle symlinks and non-existent target files.
	if [ -n "$FILE" ]; then
		RESOLVED=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE" 2>/dev/null)
		PLANS_DIR=$(python3 -c "import os; print(os.path.realpath(os.path.expanduser('~/.claude/plans')))" 2>/dev/null)
		if [ -n "$RESOLVED" ] && [ -n "$PLANS_DIR" ] && [[ "$RESOLVED" == "$PLANS_DIR"/* ]]; then
			exit 0
		fi
	fi

	echo "[block-edit-on-main] BLOCKED: refusing to edit '${FILE}' on branch '${BRANCH}'." >&2
	echo "Preferred: create a worktree: git worktree add ../<repo>.worktrees/<topic> -b claude/<topic>" >&2
	echo "Fallback (branch in place):   git checkout -b claude/<topic>" >&2
	exit 2
fi

exit 0
