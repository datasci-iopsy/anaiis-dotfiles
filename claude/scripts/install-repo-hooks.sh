#!/usr/bin/env bash
# install-repo-hooks.sh -- add standard hooks to the current git repo
#
# Run once from any project root after cloning on a new machine.
# Safe to re-run -- migrates stale direct-path hooks automatically.
#
# Usage:
#   cd /path/to/repo
#   bash ~/.claude/scripts/install-repo-hooks.sh

set -euo pipefail

HOOK_DIR="$(git rev-parse --git-dir 2>/dev/null || true)/hooks"
if [ -z "$HOOK_DIR" ] || [ "$HOOK_DIR" = "/hooks" ]; then
	echo "ERROR: not inside a git repository." >&2
	exit 1
fi

HOOK_FILE="$HOOK_DIR/pre-commit"

# Marker strings used to detect hook state
DISPATCHER_MARKER='repo-pre-commit.sh'
STALE_MARKER='lint-staged.sh'

# The single line repos call (path never changes)
DISPATCHER_LINE='bash "$HOME/.claude/hooks/repo-pre-commit.sh"'

# ---------------------------------------------------------------------------
# _migrate: replace old direct-path lint lines with the dispatcher call.
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
	awk -v line="$DISPATCHER_LINE" '
        NR == 1 { print; print ""; print "# Dotfiles lint hooks (managed by ~/anaiis-dotfiles -- never edit this line)"; print line; next }
        { print }
    ' "${tmp}.2" >"$hook"

	rm -f "$tmp" "${tmp}.2"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [ ! -f "$HOOK_FILE" ]; then
	# No existing hook -- create a fresh one
	cat >"$HOOK_FILE" <<'EOF'
#!/usr/bin/env bash
# Pre-commit hooks (managed by ~/anaiis-dotfiles)
# To update: bash ~/.claude/scripts/install-repo-hooks.sh

# Dotfiles lint hooks (managed by ~/anaiis-dotfiles -- never edit this line)
bash "$HOME/.claude/hooks/repo-pre-commit.sh"
EOF
	chmod +x "$HOOK_FILE"
	echo "  created  $HOOK_FILE"

elif grep -qF "$DISPATCHER_MARKER" "$HOOK_FILE"; then
	echo "  ok       $HOOK_FILE (dispatcher already present)"

elif grep -qF "$STALE_MARKER" "$HOOK_FILE"; then
	# Migrate old direct-path references to the dispatcher
	_migrate "$HOOK_FILE"
	chmod +x "$HOOK_FILE"
	echo "  migrated $HOOK_FILE (replaced direct-path lint calls with dispatcher)"

else
	# Hook exists but has no lint hooks -- append dispatcher
	printf '\n# Dotfiles lint hooks (managed by ~/anaiis-dotfiles -- never edit this line)\n%s\n' \
		"$DISPATCHER_LINE" >>"$HOOK_FILE"
	echo "  updated  $HOOK_FILE (appended dispatcher)"
fi

echo ""
echo "Done. Pre-commit hook active for this repo."
echo "Bypass: SKIP_R_LINT=1 git commit   |   SKIP_RUFF=1 git commit   |   SKIP_SHFMT=1 git commit   |   SKIP_SQLFMT=1 git commit"
