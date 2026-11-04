#!/usr/bin/env bash
# tests/lib/fresh-home.sh -- build a throwaway HOME for a test. Source this file; do not run it.
#
# Use:
#   . "$REPO_DIR/tests/lib/fresh-home.sh"
#   H="$(fresh_home_new "$REPO_DIR")"
#   trap 'rm -rf "$H"' EXIT
#   HOME="$H" bash some-script.sh
#
# The new HOME holds ~/.claude/{hooks,scripts,rules,commands,skills,agents,memory} as links to
# <repo_dir>/claude/<name>. Nothing else exists: no plans folder, no projects folder, no shell
# config. That is the state of a fresh machine. The function reads and writes only inside the new
# folder, and it never reads the real HOME.
#
# Why the links point at repo_dir: hooks call $HOME/.claude/scripts/... at run time. The live
# links point at the MAIN checkout, so a test in a linked worktree would run the wrong code.

fresh_home_new() {
	local repo_dir="$1" home name
	home="$(mktemp -d "${TMPDIR:-/tmp}/fresh-home.XXXXXX")" || return 1
	mkdir -p "$home/.claude"
	for name in hooks scripts rules commands skills agents memory; do
		ln -s "$repo_dir/claude/$name" "$home/.claude/$name"
	done
	printf '%s\n' "$home"
}
