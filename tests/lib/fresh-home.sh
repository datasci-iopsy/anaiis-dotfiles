#!/usr/bin/env bash
# tests/lib/fresh-home.sh -- build a throwaway HOME for a test. Source this file; do not run it.
#
# Use:
#   . "$REPO_DIR/tests/lib/fresh-home.sh"
#   H="$(fresh_home_new "$REPO_DIR")"
#   trap 'rm -rf "$H"' EXIT
#   HOME="$H" bash some-script.sh
#
# The new HOME holds ~/.claude/{hooks,scripts,rules,commands,skills,agents} as links to
# <repo_dir>/claude/<name>, and ~/.claude/memory as a real folder with a fixture MEMORY.md, as
# install.sh leaves it. repo_dir may be relative; the function makes it absolute and returns 1
# when it is not a folder. Nothing else exists: no plans folder, no projects folder, no shell
# config. That is the state of a fresh machine. The function reads and writes only inside the new
# folder, and it never reads the real HOME.
#
# Why the links point at repo_dir: hooks call $HOME/.claude/scripts/... at run time. The live
# links point at the MAIN checkout, so a test in a linked worktree would run the wrong code.

fresh_home_new() {
	local repo_dir home name
	# A relative path would make each link resolve against $home/.claude and dangle. Make it absolute
	# first. The logical pwd keeps an absolute argument exactly as the caller wrote it. An empty
	# CDPATH stops cd from picking another folder with the same name and printing its path.
	repo_dir="$(CDPATH='' cd -- "$1" && pwd)" || return 1
	home="$(mktemp -d "${TMPDIR:-/tmp}/fresh-home.XXXXXX")" || return 1
	mkdir -p "$home/.claude"
	for name in hooks scripts rules commands skills agents; do
		ln -s "$repo_dir/claude/$name" "$home/.claude/$name"
	done
	mkdir -p "$home/.claude/memory"
	printf '# Global Memory Index\n' >"$home/.claude/memory/MEMORY.md"
	printf '%s\n' "$home"
}
