#!/usr/bin/env bash
# ~/anaiis-dotfiles/install.sh
# Run once on a new machine (or after moving the repo) to:
#   1. Create ~/anaiis-dotfiles as a canonical symlink to wherever this repo lives
#   2. Symlink the Claude policy stack into ~/.claude/
#   3. Wire PATH and source shared.bash into ~/.bashrc
# Safe to re-run — idempotent.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Always resolve to the main worktree — never let a linked worktree become canonical
if git -C "$DOTFILES" rev-parse --git-dir >/dev/null 2>&1; then
	DOTFILES="$(git -C "$DOTFILES" worktree list --porcelain | awk '/^worktree/{sub(/^worktree /, ""); print; exit}')"
	if [ -z "$DOTFILES" ]; then
		echo "error: could not resolve canonical worktree path; git repository may be corrupted" >&2
		exit 1
	fi
fi
CANONICAL="$HOME/anaiis-dotfiles"

symlink() {
	local src="$1" dst="$2"
	mkdir -p "$(dirname "$dst")"
	if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
		echo "  ok   $dst"
	elif [ -e "$dst" ] && [ ! -L "$dst" ]; then
		echo "  SKIP $dst (real file exists, back it up and remove it first)"
	else
		ln -sf "$src" "$dst"
		echo "  link $dst -> $src"
	fi
}

copy_template() {
	local src="$1" dst="$2"
	mkdir -p "$(dirname "$dst")"
	if [ -e "$dst" ]; then
		echo "  ok   $dst (already exists)"
	else
		cp "$src" "$dst"
		echo "  copy $dst (from template)"
	fi
}

echo "=== Canonical path ==="
if [ "$DOTFILES" != "$CANONICAL" ]; then
	if [ -e "$CANONICAL" ] && [ ! -L "$CANONICAL" ]; then
		echo "  SKIP $CANONICAL (real directory exists — move or remove it first)"
	else
		ln -sfn "$DOTFILES" "$CANONICAL"
		echo "  link $CANONICAL -> $DOTFILES"
	fi
else
	echo "  ok   $CANONICAL (repo is already at canonical location)"
fi

echo ""
echo "=== Claude Code: Config files ==="
symlink "$CANONICAL/claude/settings.json" "$HOME/.claude/settings.json"
symlink "$CANONICAL/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
symlink "$CANONICAL/claude/keybindings.json" "$HOME/.claude/keybindings.json"
symlink "$CANONICAL/claude/RTK.md" "$HOME/.claude/RTK.md"

echo ""
echo "=== Claude Code: Directories ==="
symlink "$CANONICAL/claude/rules" "$HOME/.claude/rules"
symlink "$CANONICAL/claude/commands" "$HOME/.claude/commands"
symlink "$CANONICAL/claude/skills" "$HOME/.claude/skills"
symlink "$CANONICAL/claude/agents" "$HOME/.claude/agents"
symlink "$CANONICAL/claude/hooks" "$HOME/.claude/hooks"
symlink "$CANONICAL/claude/scripts" "$HOME/.claude/scripts"

echo ""
echo "=== Shell config (~/.bashrc) ==="
BASHRC="$HOME/.bashrc"
if grep -qF 'anaiis-dotfiles/bin' "$BASHRC" 2>/dev/null; then
	sed -i '' 's|.*anaiis-dotfiles/bin.*|export PATH="$HOME/anaiis-dotfiles/bin:$PATH"|' "$BASHRC"
	echo "  ok   PATH line (canonical)"
else
	printf '\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\n' >>"$BASHRC"
	echo "  add  PATH -> $BASHRC"
fi
if grep -qF 'anaiis-dotfiles/bash/shared.bash' "$BASHRC" 2>/dev/null; then
	echo "  ok   shared.bash source line"
else
	if grep -qF '.bashrc.local' "$BASHRC" 2>/dev/null; then
		sed -i '' '/\.bashrc\.local/i\
source "$HOME/anaiis-dotfiles/bash/shared.bash"
' "$BASHRC"
	else
		printf '\nsource "$HOME/anaiis-dotfiles/bash/shared.bash"\n' >>"$BASHRC"
	fi
	echo "  add  source shared.bash -> $BASHRC"
fi

echo ""
echo "=== Claude Code: Machine-local config (copy-once, then edit) ==="
copy_template "$DOTFILES/claude/settings.local.json.template" \
	"$HOME/.claude/settings.local.json"
copy_template "$DOTFILES/claude/CLAUDE.local.md.template" \
	"$HOME/.claude/CLAUDE.local.md"

echo ""
echo "=== Claude Code: graphify (vendored) ==="
bash "$CANONICAL/claude/scripts/install-graphify.sh"

echo ""
echo "=== Claude Code: CLI tools ==="
symlink "$CANONICAL/claude/scripts/cleanup-sessions.py" "$HOME/.local/bin/claude-cleanup"

echo ""
echo "=== R Style ==="
symlink "$CANONICAL/.lintr" "$HOME/.lintr"

echo ""
echo "=== Homebrew packages ==="
if command -v brew >/dev/null 2>&1; then
	echo "  Brewfile present. Run to install or sync:"
	echo "      bash $CANONICAL/claude/scripts/brew-sync.sh install"
else
	echo "  brew not found, skipping (install Homebrew first if needed)"
fi

echo ""
echo "Done."
echo ""
echo "=== web-verify CLI (optional) ==="
echo ""
echo "The PATH and shared.bash source lines were wired into ~/.bashrc above."
echo "For zsh or fish, add manually:"
echo "    export PATH=\"\$HOME/anaiis-dotfiles/bin:\$PATH\""
echo ""
echo "Cleanup (if upgrading from a prior install):"
echo "  rm -f \"\$HOME/.mcp.json\"   # the github MCP entry was removed; this clears any dangling symlink"
echo "  rm -f \"\$HOME/.bashrc\" \"\$HOME/.bash_profile\" \"\$HOME/.bashrc.local\"   # only if these were dotfiles symlinks; back up first"
echo ""
echo "Next steps:"
echo "  1. Edit ~/.claude/settings.local.json , set GITHUB_TOKEN and model"
echo "  2. Edit ~/.claude/CLAUDE.local.md     , note machine-specific environment"
echo "  3. Run ~/.claude/scripts/seed-memory.sh from any project root to init memory"
echo "  4. Run ~/.claude/scripts/install-repo-hooks.sh in repos that need lint hooks"
echo ""
echo "=== Suggested tools (not installed by this script) ==="
echo ""
echo "LibreOffice, required for .docx ingestion on Linux; optional on macOS (textutil"
echo "is used there instead, but LibreOffice is available as a fallback)."
echo ""
echo "  macOS:  brew install --cask libreoffice"
echo "  Linux:  sudo apt install libreoffice    # Debian/Ubuntu"
echo "          brew install --cask libreoffice # Linuxbrew"
