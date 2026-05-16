#!/usr/bin/env bash
# ~/.dotfiles/install.sh
# Run once on a new machine to symlink the Claude policy stack into place.
# Safe to re-run, skips anything already correctly linked.
#
# This dotfiles repo no longer manages your shell config. The only shell-
# adjacent piece is bin/web-verify, a CLI wrapper for serving + Playwright
# verify + teardown. To use it, add this directory to your PATH (instructions
# printed below).

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

echo "=== Claude Code: Config files ==="
symlink "$DOTFILES/claude/settings.json" "$HOME/.claude/settings.json"
symlink "$DOTFILES/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
symlink "$DOTFILES/claude/keybindings.json" "$HOME/.claude/keybindings.json"

echo ""
echo "=== Claude Code: Directories ==="
symlink "$DOTFILES/claude/rules" "$HOME/.claude/rules"
symlink "$DOTFILES/claude/commands" "$HOME/.claude/commands"
symlink "$DOTFILES/claude/skills" "$HOME/.claude/skills"
symlink "$DOTFILES/claude/agents" "$HOME/.claude/agents"
symlink "$DOTFILES/claude/hooks" "$HOME/.claude/hooks"
symlink "$DOTFILES/claude/scripts" "$HOME/.claude/scripts"

echo ""
echo "=== Claude Code: Machine-local config (copy-once, then edit) ==="
copy_template "$DOTFILES/claude/settings.local.json.template" \
	"$HOME/.claude/settings.local.json"
copy_template "$DOTFILES/claude/CLAUDE.local.md.template" \
	"$HOME/.claude/CLAUDE.local.md"

echo ""
echo "=== Claude Code: graphify (vendored) ==="
bash "$DOTFILES/claude/scripts/install-graphify.sh"

echo ""
echo "=== Claude Code: CLI tools ==="
symlink "$DOTFILES/claude/scripts/cleanup-sessions.py" "$HOME/.local/bin/claude-cleanup"

echo ""
echo "=== R Style ==="
symlink "$DOTFILES/.lintr" "$HOME/.lintr"

echo ""
echo "Done."
echo ""
echo "=== web-verify CLI (optional) ==="
echo ""
echo "If you use the web-verify command directly,"
echo "add this single line to your shell config (~/.bashrc, ~/.zshrc, or"
echo "~/.config/fish/config.fish, choose whichever your shell reads):"
echo ""
echo "    export PATH=\"\$HOME/.dotfiles/bin:\$PATH\""
echo ""
echo "Works in bash, zsh, fish, or any POSIX shell. No 'source' required."
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
