#!/usr/bin/env bash
# repo-commit-msg.sh -- stable dispatcher for repo commit-msg hooks
#
# Repos call this single file via their .git/hooks/commit-msg. Git passes the
# commit message file as argument 1.
#
# The hook checks the message with commit-msg-lint.sh. It checks only in a repo
# that opts in with a .conventional-commits file in its working tree at the repo
# root, because other repos use other commit conventions (decision D-005). The
# file need not be tracked by git.
#
# The hook exits 0 at once when:
#   - SKIP_COMMIT_LINT=1 is set,
#   - the repo has no .conventional-commits file (or there is no repo root),
#   - $HOME/.claude/scripts/commit-msg-lint.sh does not exist. Missing tooling
#     must never block a commit.
# Otherwise the hook returns the exit code of the validator.
#
# Stable path (repos reference this; never rename it):
#   bash "$HOME/.claude/hooks/repo-commit-msg.sh" "$1"
#
# Bypass flag (for the user only):
#   SKIP_COMMIT_LINT=1 git commit  -- skip the message lint

set -u

[ "${SKIP_COMMIT_LINT:-0}" = "1" ] && exit 0

# Outside a repo, root is empty and the marker test fails, so the hook exits 0.
root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -f "$root/.conventional-commits" ] || exit 0

lint="$HOME/.claude/scripts/commit-msg-lint.sh"
[ -f "$lint" ] || exit 0

exec bash "$lint" "${1:-}"
