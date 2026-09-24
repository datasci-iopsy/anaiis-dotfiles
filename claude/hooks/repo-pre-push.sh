#!/usr/bin/env bash
# repo-pre-push.sh -- stable dispatcher for repo pre-push hooks
#
# Repos call this single file via their .git/hooks/pre-push. Runs the repo's
# full test suite (tests/run-all.sh) before anything leaves the machine.
# Commits stay fast: repo-pre-commit.sh runs only the staged-file linters.
#
# Stable path (repos reference this; never rename it):
#   bash "$HOME/.claude/hooks/repo-pre-push.sh"
#
# Git passes the remote name and URL as arguments (ignored) and, on stdin, one
# "<local ref> <local sha> <remote ref> <remote sha>" line per ref it will
# update. The list is empty when everything is up to date, and a local sha of
# all zeros marks a deletion. The suite runs only when at least one line sends
# commits, so a no-op push returns git's own "Everything up-to-date" at once.
#
# Bypass flag:
#   SKIP_TESTS=1  git push  -- skip the test suite

set -euo pipefail

ZERO_SHA=0000000000000000000000000000000000000000
SENDS_COMMITS=0
while read -r _local_ref local_sha _remote_ref _remote_sha; do
	if [ "$local_sha" != "$ZERO_SHA" ]; then
		SENDS_COMMITS=1
	fi
done
if [ "$SENDS_COMMITS" -eq 0 ]; then
	exit 0
fi

# Run the test suite if the repo has one. SKIP_TESTS=1 to bypass.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ "${SKIP_TESTS:-0}" != "1" ] && [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/tests/run-all.sh" ]; then
	bash "$REPO_ROOT/tests/run-all.sh"
fi
