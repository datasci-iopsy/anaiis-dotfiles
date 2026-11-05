#!/usr/bin/env bash
# ~/anaiis-dotfiles/install.sh
# Run once on a new machine (or after moving the repo) to:
#   1. Create ~/anaiis-dotfiles as a canonical symlink to wherever this repo lives
#   2. Symlink the Claude policy stack into ~/.claude/, and remove the old
#      CLAUDE.md link from that folder (rules/context.md replaces the file).
#      ~/.claude/memory is a local folder, not a link: a link becomes a folder
#      that holds a copy of its data
#   3. Wire PATH and source shared.bash into ~/.bashrc
#   4. Add the GitHub host keys to ~/.ssh/known_hosts (SSH git protocol only)
# Safe to re-run: idempotent.

set -euo pipefail

# Usage:
#   bash install.sh                   full install
#   bash install.sh --symlinks-only   steps 1 and 2 only (the old CLAUDE.md link
#                                     is removed here too); stops before ~/.bashrc,
#                                     CLI tools, R style, and Homebrew
#                                     (what CI runs to build the ~/.claude tree)
#   bash install.sh --bashrc-only     step 3 only: wire $HOME/.bashrc (and check
#                                     $HOME/.bash_profile) and exit (what
#                                     tests/test-install-bashrc.sh runs against
#                                     a throwaway HOME)
#   bash install.sh --hostkeys-only   step 4 only: add the GitHub host keys to
#                                     $HOME/.ssh/known_hosts and exit. It acts only
#                                     when gh is installed, its git protocol is ssh,
#                                     and the file has no github.com entry. Run it
#                                     again after gh auth login.
MODE="${1:-}"
case "$MODE" in
	--symlinks-only | --bashrc-only | --hostkeys-only | "") ;;
	*)
		echo "usage: bash install.sh [--symlinks-only|--bashrc-only|--hostkeys-only]" >&2
		exit 2
		;;
esac

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Always resolve to the main worktree. Never let a linked worktree become canonical.
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
		# -n: replace a link to a folder; do not make a new link inside that folder.
		ln -sfn "$src" "$dst"
		echo "  link $dst -> $src"
	fi
}

# Remove the old CLAUDE.md link from $HOME/.claude (decision D-003). The repo has no CLAUDE.md now.
# The function acts only on a symlink whose target ends in /anaiis-dotfiles/claude/CLAUDE.md.
# It leaves a real file or a link to another target alone. Claude Code still reads such a file, so the
# function prints a note for each. It also keeps the link while $CANONICAL has no rules/context.md,
# because that checkout can be older than this installer. The next run removes the link.
remove_old_claude_md_link() {
	local link="$HOME/.claude/CLAUDE.md" target
	if [ -L "$link" ]; then
		target="$(readlink "$link")"
		case "$target" in
			*/anaiis-dotfiles/claude/CLAUDE.md)
				if [ ! -f "$CANONICAL/claude/rules/context.md" ]; then
					echo "  note  $link kept: $CANONICAL/claude/rules/context.md is missing. Update that checkout, then run install.sh again."
					return 0
				fi
				rm -f "$link"
				echo "  unlink $link (old link to $target; rules/context.md replaces it)"
				;;
			*)
				echo "  note  $link is a link to $target, not the old dotfiles link. Claude Code still reads it. Left in place."
				;;
		esac
	elif [ -e "$link" ]; then
		echo "  note  $link is a real file. Claude Code still reads it. Left in place."
	fi
}

# Keep $HOME/.claude/memory as a local folder, not a link into the repo. Once the repo stops tracking
# claude/memory/, a git pull deletes the data behind a link. The function copies before it removes,
# and it never deletes memory data.
ensure_local_memory() {
	local dst="$HOME/.claude/memory" target tmp
	if [ -L "$dst" ]; then
		target="$(readlink "$dst")"
		if [ -d "$dst" ]; then
			# Copy into a temp folder next to the link first. If the copy fails, set -e stops here and the link stays.
			tmp="$(mktemp -d "$dst.tmp.XXXXXX")"
			cp -Rp "$dst/." "$tmp/"
			rm "$dst"
			mv "$tmp" "$dst"
			echo "  migrated $dst (copied from $target, now a local folder)"
		else
			rm "$dst"
			mkdir "$dst"
			echo "  WARN $dst linked to $target, which is gone. Made an empty folder. Recover the index with: git -C $CANONICAL show HEAD:claude/memory/MEMORY.md"
		fi
	elif [ -d "$dst" ]; then
		echo "  ok   $dst (local folder)"
	elif [ -e "$dst" ]; then
		echo "  SKIP $dst (real file exists, back it up and remove it first)"
	else
		mkdir -p "$dst"
		printf '# Global Memory Index\n' >"$dst/MEMORY.md"
		echo "  created $dst (empty MEMORY.md index)"
	fi
}

# Step 3: wire PATH and the shared.bash source line into $HOME/.bashrc.
# A function so --bashrc-only can run exactly this phase against a throwaway
# HOME; the body is what the full install has always run.
wire_bashrc() {
	echo ""
	echo "=== Shell config (~/.bashrc) ==="
	local BASHRC="$HOME/.bashrc"
	# shellcheck disable=SC2016 # $HOME stays literal: the line is written into ~/.bashrc as text
	local PATH_LINE='export PATH="$HOME/anaiis-dotfiles/bin:$PATH"'
	local tmp_bashrc
	# A fresh machine has no ~/.bashrc, and awk below fails on a missing file.
	[ -f "$BASHRC" ] || touch "$BASHRC"
	# Rewrite unless exactly one canonical line is in place, so a re-run of a good file changes nothing.
	if [ "$(grep -c 'anaiis-dotfiles/bin' "$BASHRC")" != 1 ] || ! grep -qxF "$PATH_LINE" "$BASHRC"; then
		tmp_bashrc="$(mktemp "${TMPDIR:-/tmp}/bashrc_path_fix.XXXXXX")" || return 1
		# Strip any prior form (bare export, indented export inside an if-guard, or
		# duplicates), then append the single canonical line. Idempotent by design.
		# shellcheck disable=SC2015 # the || branch removes the temp file when awk or mv fails
		awk '
	/if.*anaiis-dotfiles\/bin/  { in_guard=1; next }
	in_guard && /^[[:space:]]*fi[[:space:]]*$/ { in_guard=0; next }
	/anaiis-dotfiles\/bin/      { next }
	{ print }
' "$BASHRC" >"$tmp_bashrc" \
			&& mv "$tmp_bashrc" "$BASHRC" \
			|| {
				rm -f "$tmp_bashrc"
				return 1
			}
		printf '\n%s\n' "$PATH_LINE" >>"$BASHRC"
	fi
	echo "  ok   PATH line (canonical)"
	# A line that starts with # is a comment: the shell never reads it, so it is not a source line.
	if grep -qE '^[[:space:]]*([^[:space:]#].*)?anaiis-dotfiles/bash/shared[.]bash' "$BASHRC" 2>/dev/null; then
		echo "  ok   shared.bash source line"
	else
		if grep -qF '.bashrc.local' "$BASHRC" 2>/dev/null; then
			# shellcheck disable=SC2016 # $HOME stays literal in the inserted line
			sed -i '' '/\.bashrc\.local/i\
source "$HOME/anaiis-dotfiles/bash/shared.bash"
' "$BASHRC"
		else
			# shellcheck disable=SC2016 # $HOME stays literal in the appended line
			printf '\nsource "$HOME/anaiis-dotfiles/bash/shared.bash"\n' >>"$BASHRC"
		fi
		echo "  add  source shared.bash -> $BASHRC"
	fi

	# A login shell (Terminal.app starts one) reads ~/.bash_profile, not ~/.bashrc. Make sure
	# something sources ~/.bashrc, without editing a file the user wrote.
	local PROFILE="$HOME/.bash_profile"
	# shellcheck disable=SC2016 # $HOME stays literal: the line is written into ~/.bash_profile as text
	local PROFILE_LINE='[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
	if [ -f "$PROFILE" ]; then
		# The name must end at .bashrc: a line that sources only .bashrc.local does not load .bashrc.
		if grep -qE '^[[:space:]]*([^[:space:]#].*)?[.]bashrc([^[:alnum:]_.-]|$)' "$PROFILE"; then
			echo "  ok   $PROFILE mentions .bashrc"
		else
			echo "  note  $PROFILE never sources ~/.bashrc. Add this line to it: $PROFILE_LINE"
		fi
	elif [ -f "$HOME/.bash_login" ] || [ -f "$HOME/.profile" ]; then
		# bash reads only the first of .bash_profile, .bash_login, .profile. A new
		# .bash_profile would hide the others.
		echo "  note  no ~/.bash_profile created: bash would then ignore ~/.bash_login and ~/.profile. Add this line to the one you use: $PROFILE_LINE"
	else
		printf '%s\n' "$PROFILE_LINE" >"$PROFILE"
		echo "  add  $PROFILE (sources ~/.bashrc)"
	fi
}

# Step 4: add the GitHub host keys to $HOME/.ssh/known_hosts (decision D-012).
# Plugin clones over SSH fail without them. The function never aborts the installer:
# every refusal prints one reason and returns 0. It writes only when the fingerprints
# of the keys that gh api meta lists equal the fingerprints in the same response.
# ssh-keygen reads the passwd home and ignores $HOME, so each call passes -f.
wire_github_hostkeys() {
	echo ""
	echo "=== GitHub host keys (~/.ssh/known_hosts) ==="
	local known="$HOME/.ssh/known_hosts" proto keys prints want got tmp count
	if ! command -v gh >/dev/null 2>&1; then
		echo "  skip  gh not found. Install it and run gh auth login, then: bash install.sh --hostkeys-only"
		return 0
	fi
	proto="$(gh config get git_protocol 2>/dev/null)" || proto=""
	if [ "$proto" != "ssh" ]; then
		echo "  skip  gh git protocol is \"${proto:-unset}\", not ssh. No host key is needed."
		return 0
	fi
	if ssh-keygen -F github.com -f "$known" >/dev/null 2>&1; then
		echo "  ok   github.com host key already in $known"
		return 0
	fi
	keys="$(gh api meta --jq '.ssh_keys[]' 2>/dev/null)" || keys=""
	prints="$(gh api meta --jq '.ssh_key_fingerprints[]' 2>/dev/null)" || prints=""
	if [ -z "$keys" ] || [ -z "$prints" ]; then
		echo "  skip  gh could not read the GitHub host keys. Run gh auth status, then: bash install.sh --hostkeys-only"
		return 0
	fi
	tmp="$(mktemp "${TMPDIR:-/tmp}/github_hostkeys.XXXXXX")" || return 0
	printf '%s\n' "$keys" | sed -e '/^$/d' -e 's/^/github.com /' >"$tmp"
	# The API lists fingerprints without the SHA256: prefix that ssh-keygen prints. Compare both bare.
	want="$(printf '%s\n' "$prints" | sed 's/^SHA256://' | LC_ALL=C sort -u)"
	got="$(ssh-keygen -lf "$tmp" 2>/dev/null | awk '{print $2}' | sed 's/^SHA256://' | LC_ALL=C sort -u)" || got=""
	if [ -z "$got" ] || [ "$want" != "$got" ]; then
		rm -f "$tmp"
		echo "  skip  fingerprints of the fetched keys differ from the GitHub list. Nothing written."
		return 0
	fi
	# The group runs inside a condition, so a failed write prints one reason and does not abort the installer.
	if ! {
		[ -d "$HOME/.ssh" ] || mkdir -m 700 "$HOME/.ssh"
		# A known_hosts file without a final newline would join its last line to the first new line.
		if [ -s "$known" ] && [ -n "$(tail -c 1 "$known")" ]; then
			echo >>"$known"
		fi
		cat "$tmp" >>"$known"
	} 2>/dev/null; then
		rm -f "$tmp"
		echo "  skip  could not write $known. Check the permissions of ~/.ssh, then: bash install.sh --hostkeys-only"
		return 0
	fi
	count="$(grep -c . "$tmp")"
	echo "  add  github.com host keys ($count keys) -> $known"
	echo "       ED25519 fingerprint: $(ssh-keygen -lf "$tmp" | awk '/\(ED25519\)/ {print $2}')"
	rm -f "$tmp"
}

if [ "$MODE" = "--bashrc-only" ]; then
	wire_bashrc
	exit 0
fi

if [ "$MODE" = "--hostkeys-only" ]; then
	wire_github_hostkeys
	exit 0
fi

echo "=== Canonical path ==="
if [ "$DOTFILES" != "$CANONICAL" ]; then
	if [ -e "$CANONICAL" ] && [ ! -L "$CANONICAL" ]; then
		echo "  SKIP $CANONICAL (real directory exists, move or remove it first)"
	elif [ -L "$CANONICAL" ] && [ "$(readlink "$CANONICAL")" = "$DOTFILES" ]; then
		echo "  ok   $CANONICAL -> $DOTFILES"
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
symlink "$CANONICAL/claude/keybindings.json" "$HOME/.claude/keybindings.json"
remove_old_claude_md_link

echo ""
echo "=== Claude Code: Directories ==="
symlink "$CANONICAL/claude/rules" "$HOME/.claude/rules"
symlink "$CANONICAL/claude/commands" "$HOME/.claude/commands"
symlink "$CANONICAL/claude/skills" "$HOME/.claude/skills"
symlink "$CANONICAL/claude/agents" "$HOME/.claude/agents"
symlink "$CANONICAL/claude/hooks" "$HOME/.claude/hooks"
symlink "$CANONICAL/claude/scripts" "$HOME/.claude/scripts"
ensure_local_memory

if [ "$MODE" = "--symlinks-only" ]; then
	echo ""
	echo "Done (--symlinks-only: skipped shell config, CLI tools, R style, Homebrew)."
	exit 0
fi

wire_bashrc
wire_github_hostkeys

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
	echo "  Several admin profiles share the prefix? Run once:"
	echo "      sudo bash $CANONICAL/claude/scripts/brew-share.sh"
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
echo "  rm -f \"\$HOME/.claude/settings.local.json\" \"\$HOME/.claude/CLAUDE.local.md\"   # dead user-level local-config layer, removed 2026-07 (Claude Code never reads either path)"
echo ""
echo "Next steps:"
echo "  1. Run ~/.claude/scripts/seed-memory.sh from any project root to init memory"
echo "  2. Run ~/.claude/scripts/install-repo-hooks.sh in repos that need lint hooks"
echo ""
echo "=== Suggested tools (not installed by this script) ==="
echo ""
echo "LibreOffice, required for .docx ingestion on Linux; optional on macOS (textutil"
echo "is used there instead, but LibreOffice is available as a fallback)."
echo ""
echo "  macOS:  brew install --cask libreoffice"
echo "  Linux:  sudo apt install libreoffice    # Debian/Ubuntu"
echo "          brew install --cask libreoffice # Linuxbrew"
