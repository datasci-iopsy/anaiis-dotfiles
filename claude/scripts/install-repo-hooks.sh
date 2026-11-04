#!/usr/bin/env bash
# install-repo-hooks.sh -- add standard hooks to the current git repo
#
# Installs three dispatcher hooks:
#   pre-commit -> bash "$HOME/.claude/hooks/repo-pre-commit.sh"         (staged-file linters)
#   pre-push   -> bash "$HOME/.claude/hooks/repo-pre-push.sh"           (full test suite)
#   commit-msg -> bash "$HOME/.claude/hooks/repo-commit-msg.sh" "$1"    (message lint, opt-in)
#
# The commit-msg hook checks a message only in a repo whose working tree has a
# .conventional-commits file at its root. Other repos accept any message.
#
# Run once from any project root after cloning on a new machine.
# Safe to re-run -- migrates stale direct-path pre-commit hooks automatically
# and adds the pre-push and commit-msg hooks to repos that lack them.
#
# Usage:
#   cd /path/to/repo
#   bash ~/.claude/scripts/install-repo-hooks.sh

# SC2016: the dispatcher lines hold literal "$HOME" and "$1" on purpose; each hook expands them.
# shellcheck disable=SC2016
set -euo pipefail

# Ask git where hooks live. In a linked worktree this is the common hooks
# folder, and it honors core.hooksPath. Git prints the path relative to the
# current folder, so make it absolute.
HOOK_DIR="$(git rev-parse --git-path hooks 2>/dev/null || true)"
if [ -z "$HOOK_DIR" ]; then
	echo "ERROR: not inside a git repository." >&2
	exit 1
fi
case "$HOOK_DIR" in
	/*) ;;
	*) HOOK_DIR="$PWD/$HOOK_DIR" ;;
esac
mkdir -p "$HOOK_DIR"

# Marker for the legacy pre-commit form (direct lint-script paths)
STALE_MARKER='lint-staged.sh'

# The single line each hook calls (paths never change)
PRE_COMMIT_LINE='bash "$HOME/.claude/hooks/repo-pre-commit.sh"'
PRE_PUSH_LINE='bash "$HOME/.claude/hooks/repo-pre-push.sh"'
COMMIT_MSG_LINE='bash "$HOME/.claude/hooks/repo-commit-msg.sh" "$1"'

# ---------------------------------------------------------------------------
# _migrate: replace old direct-path lint lines with the pre-commit dispatcher.
# Preserves all other hook content (e.g. repo-specific lock file guards).
# ---------------------------------------------------------------------------
_migrate() {
	local hook="$1"
	local tmp
	tmp=$(mktemp)

	# Strip old lint lines and their dotfiles-added comments; keep everything else
	awk '
        /# R style lint \(added by install-repo-hooks\.sh\)/ { next }
        /# Python ruff lint \(added by install-repo-hooks\.sh\)/ { next }
        /# -+ R style lint.*-+/ { next }
        /r-lint-staged\.sh/ { next }
        /ruff-lint-staged\.sh/ { next }
        { print }
    ' "$hook" >"$tmp"

	# Collapse runs of 3+ blank lines left by removal down to one blank line
	awk 'BEGIN{blank=0} /^[[:space:]]*$/{blank++; if(blank<=1) print; next} {blank=0; print}' \
		"$tmp" >"${tmp}.2"

	# Inject dispatcher after the shebang line (line 1)
	awk -v line="$PRE_COMMIT_LINE" '
        NR == 1 { print; print ""; print "# Dotfiles lint hooks (managed by ~/anaiis-dotfiles -- never edit this line)"; print line; next }
        { print }
    ' "${tmp}.2" >"$hook"

	rm -f "$tmp" "${tmp}.2"
}

# ---------------------------------------------------------------------------
# _install <hook-name> <dispatcher-line> <marker> <label> <title>
#   Create the hook if absent; report ok if its marker is already present;
#   otherwise append the dispatcher line, preserving existing content.
#   pre-commit additionally migrates the legacy direct-path form.
# ---------------------------------------------------------------------------
_install() {
	local name="$1" line="$2" marker="$3" label="$4" title="$5"
	local hook="$HOOK_DIR/$name"

	if [ ! -f "$hook" ]; then
		printf '#!/usr/bin/env bash\n# %s hooks (managed by ~/anaiis-dotfiles)\n# To update: bash ~/.claude/scripts/install-repo-hooks.sh\n\n# Dotfiles %s hooks (managed by ~/anaiis-dotfiles -- never edit this line)\n%s\n' \
			"$title" "$label" "$line" >"$hook"
		chmod +x "$hook"
		echo "  created  $hook"

	elif grep -qF "$marker" "$hook"; then
		chmod +x "$hook"
		echo "  ok       $hook (dispatcher already present)"

	elif [ "$name" = "pre-commit" ] && grep -qF "$STALE_MARKER" "$hook"; then
		_migrate "$hook"
		chmod +x "$hook"
		echo "  migrated $hook (replaced direct-path lint calls with dispatcher)"

	else
		printf '\n# Dotfiles %s hooks (managed by ~/anaiis-dotfiles -- never edit this line)\n%s\n' \
			"$label" "$line" >>"$hook"
		chmod +x "$hook"
		echo "  updated  $hook (appended dispatcher)"
	fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

_install pre-commit "$PRE_COMMIT_LINE" 'repo-pre-commit.sh' lint Pre-commit
_install pre-push "$PRE_PUSH_LINE" 'repo-pre-push.sh' test Pre-push
_install commit-msg "$COMMIT_MSG_LINE" 'repo-commit-msg.sh' commit-msg Commit-msg

echo ""
echo "Done. Pre-commit (lint), pre-push (test suite), and commit-msg (message lint, opt-in) hooks active for this repo."
echo "Bypass: SKIP_R_LINT=1 | SKIP_RUFF=1 | SKIP_SHFMT=1 | SKIP_SQLFMT=1 | SKIP_COMMIT_LINT=1 git commit   |   SKIP_TESTS=1 git push"
