#!/bin/bash

# Read the JSON input from stdin
input=$(cat)

# Check if stop hook is already active (recursion prevention)
if command -v jq &>/dev/null; then
	stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active')
	if [[ "$stop_hook_active" = "true" ]]; then
		exit 0
	fi
fi

# Check if we're in a git repository - bail if not
if ! git rev-parse --git-dir >/dev/null 2>&1; then
	exit 0
fi

# Bail if there's no remote to push to. Every error path below asks the user
# to "push to the remote branch", meaningless without a remote, and
# unsatisfiable if signing also requires a source. This case arises when CCR
# was launched against a local repo with no github remote (sources=[]) and
# the container's cwd has a leftover .git from a cached resume.
if [[ -z "$(git remote)" ]]; then
	exit 0
fi

# Check for uncommitted changes (both staged and unstaged)
if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "[git] uncommitted changes" >&2
	exit 2
fi

# Check for untracked files that might be important
untracked_files=$(git ls-files --others --exclude-standard)
if [[ -n "$untracked_files" ]]; then
	echo "[git] untracked files" >&2
	exit 2
fi

current_branch=$(git branch --show-current)
if [[ -n "$current_branch" ]]; then
	if git rev-parse "origin/$current_branch" >/dev/null 2>&1; then
		unpushed=$(git rev-list "origin/$current_branch..HEAD" --count 2>/dev/null) || unpushed=0
		if [[ "$unpushed" -gt 0 ]]; then
			echo "[git] $unpushed unpushed commit(s) on '$current_branch'" >&2
			exit 2
		fi
	else
		unpushed=$(git rev-list "origin/HEAD..HEAD" --count 2>/dev/null) || unpushed=0
		if [[ "$unpushed" -gt 0 ]]; then
			echo "[git] $unpushed unpushed commit(s), no remote for '$current_branch'" >&2
			exit 2
		fi
	fi
fi

# Remind if deferred CodeRabbit findings exist
DEFERRED="$HOME/.claude/coderabbit-deferred.md"
if [[ -f "$DEFERRED" ]] && grep -qv '^#' "$DEFERRED" 2>/dev/null && grep -q '[^[:space:]]' "$DEFERRED" 2>/dev/null; then
	count=$(grep -c '^## ' "$DEFERRED" 2>/dev/null || echo "some")
	echo "[git] $count deferred CodeRabbit finding(s)" >&2
fi

exit 0
