#!/usr/bin/env bash
# Three verbs: install | check | dump
# install  -- brew bundle install (idempotent; safe to re-run on any machine)
# check    -- report drift between installed packages and Brewfile
# dump     -- refresh Brewfile from current machine state
set -euo pipefail

CANONICAL="$HOME/anaiis-dotfiles"
BREWFILE="$CANONICAL/Brewfile"

if ! command -v brew >/dev/null 2>&1; then
	echo "brew not found -- install Homebrew first: https://brew.sh"
	exit 0
fi

verb="${1:-}"

case "$verb" in
	install)
		brew bundle install --file="$BREWFILE"
		;;
	check)
		brew bundle check --file="$BREWFILE" --verbose
		;;
	dump)
		brew bundle dump --describe --force --file="$BREWFILE"
		echo "Brewfile updated at $BREWFILE"
		;;
	*)
		echo "Usage: brew-sync.sh <install|check|dump>"
		exit 1
		;;
esac
