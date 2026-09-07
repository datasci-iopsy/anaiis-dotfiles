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
# Git passes the remote name and URL as arguments and the refs being pushed on
# stdin; neither is needed to decide whether the suite runs, so both are
# ignored.
#
# Bypass flag:
#   SKIP_TESTS=1  git push  -- skip the test suite

set -euo pipefail

# Run the test suite if the repo has one. SKIP_TESTS=1 to bypass.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ "${SKIP_TESTS:-0}" != "1" ] && [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/tests/run-all.sh" ]; then
	bash "$REPO_ROOT/tests/run-all.sh"
fi
