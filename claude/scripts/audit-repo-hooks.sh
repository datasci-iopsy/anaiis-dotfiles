#!/usr/bin/env bash
# audit-repo-hooks.sh -- find repos with stale or missing dotfiles hook wiring
#
# Searches SEARCH_DIRS for .git/hooks/pre-commit files, then reports:
#   ok      -- pre-commit and commit-msg dispatchers present
#   stale   -- old direct-path lint references (needs install-repo-hooks.sh)
#   missing -- no lint hook at all, or no commit-msg dispatcher
#   absent  -- no pre-commit hook file
#
# maintenance-check.sh counts the lines that start with STALE, missing, or absent.
#
# Usage:
#   bash ~/.claude/scripts/audit-repo-hooks.sh
#
# Override search dirs:
#   HOOK_SEARCH_DIRS="/path/a /path/b" bash ~/.claude/scripts/audit-repo-hooks.sh

set -euo pipefail

SEARCH_DIRS=(
	"$HOME/Documents"
	"$HOME/Projects"
	"$HOME/repos"
	"$HOME/src"
)

# Allow override via env
if [ -n "${HOOK_SEARCH_DIRS:-}" ]; then
	read -ra SEARCH_DIRS <<<"$HOOK_SEARCH_DIRS"
fi

DISPATCHER_MARKER='repo-pre-commit.sh'
COMMIT_MSG_MARKER='repo-commit-msg.sh'
STALE_MARKER='-lint-staged.sh'

ok=0
stale=0
missing=0
absent=0

echo "=== Repo hook audit ==="
echo ""

for dir in "${SEARCH_DIRS[@]}"; do
	[ -d "$dir" ] || continue

	while IFS= read -r git_dir; do
		repo=$(git -C "$(dirname "$git_dir")" rev-parse --show-toplevel 2>/dev/null) || continue
		# Ask git where hooks live (core.hooksPath moves the folder). The path is relative to the repo root.
		hooks_dir=$(git -C "$repo" rev-parse --git-path hooks 2>/dev/null) || continue
		case "$hooks_dir" in
			/*) ;;
			*) hooks_dir="$repo/$hooks_dir" ;;
		esac
		hook="$hooks_dir/pre-commit"

		if [ ! -f "$hook" ]; then
			printf "  absent   %s\n" "$repo"
			absent=$((absent + 1))
		elif grep -qF -- "$DISPATCHER_MARKER" "$hook"; then
			if grep -qF -- "$COMMIT_MSG_MARKER" "$hooks_dir/commit-msg" 2>/dev/null; then
				printf "  ok       %s\n" "$repo"
				ok=$((ok + 1))
			else
				printf "  missing  %s (no commit-msg hook)\n" "$repo"
				printf "           Fix: cd %s && bash ~/.claude/scripts/install-repo-hooks.sh\n" "$repo"
				missing=$((missing + 1))
			fi
		elif grep -qF -- "$STALE_MARKER" "$hook"; then
			printf "  STALE    %s\n" "$repo"
			printf "           Fix: cd %s && bash ~/.claude/scripts/install-repo-hooks.sh\n" "$repo"
			stale=$((stale + 1))
		else
			printf "  missing  %s\n" "$repo"
			printf "           Fix: cd %s && bash ~/.claude/scripts/install-repo-hooks.sh\n" "$repo"
			missing=$((missing + 1))
		fi
	done < <(find "$dir" -maxdepth 7 -name "HEAD" -path "*/.git/HEAD" \
		! -path "*/node_modules/*" ! -path "*/.git/modules/*" \
		-exec dirname {} \; 2>/dev/null)
done

echo ""
echo "--- Summary ---"
echo "  ok:      $ok"
[ "$stale" -gt 0 ] && echo "  STALE:   $stale   (run install-repo-hooks.sh to migrate)"
[ "$missing" -gt 0 ] && echo "  missing: $missing  (run install-repo-hooks.sh to add)"
[ "$absent" -gt 0 ] && echo "  absent:  $absent   (no pre-commit hook file)"
echo ""

[ $((stale + missing)) -eq 0 ] && echo "All hooks current." || exit 1
