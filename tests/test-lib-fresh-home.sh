#!/usr/bin/env bash
# tests/test-lib-fresh-home.sh -- verify tests/lib/fresh-home.sh builds a throwaway HOME
# whose ~/.claude links point at the repo under test, and never touches the real HOME.
#
# Why this matters: hooks and scripts call $HOME/.claude/scripts/... at run time. In a linked
# worktree the live ~/.claude links point at the MAIN checkout, so a test that uses the real
# HOME exercises the wrong copy of the code. A test that uses this helper exercises the
# worktree under test.
#
# Usage: bash tests/test-lib-fresh-home.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

assert_eq() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' "$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

yesno() {
	if "$@"; then echo yes; else echo no; fi
}

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/fresh-home.sh
. "$REPO_DIR/tests/lib/fresh-home.sh"

REAL_HOME_BEFORE="$(find "$HOME" -maxdepth 1 | sort | cksum)"

H1="$(fresh_home_new "$REPO_DIR")"
H2="$(fresh_home_new "$REPO_DIR")"
trap 'rm -rf "$H1" "$H2"' EXIT

echo "--- 1. the folder"
assert_eq "1.1 first HOME is a folder" yes "$(yesno test -d "$H1")"
assert_eq "1.2 two calls return two different folders" yes "$(yesno test "$H1" != "$H2")"
assert_eq "1.3 the folder is not the real HOME" yes "$(yesno test "$H1" != "$HOME")"

echo "--- 2. the links point at the repo under test"
for name in hooks scripts rules commands skills agents memory; do
	assert_eq "2.$name link target" "$REPO_DIR/claude/$name" "$(readlink "$H1/.claude/$name")"
	assert_eq "2.$name link resolves to a folder" yes "$(yesno test -d "$H1/.claude/$name/")"
done

echo "--- 3. what the helper must leave alone"
assert_eq "3.1 plans folder is absent (fresh machine state)" no "$(yesno test -e "$H1/.claude/plans")"
assert_eq "3.2 projects folder is absent (fresh machine state)" no "$(yesno test -e "$H1/.claude/projects")"
assert_eq "3.3 real HOME listing is unchanged" "$REAL_HOME_BEFORE" "$(find "$HOME" -maxdepth 1 | sort | cksum)"

echo "--- 4. a suite that builds HOMEs with the helper removes them at exit"
# Why: test-maintenance-check.sh once built each HOME inside $(...). The subshell lost the list of
# HOMEs, so every run left them behind, one with a 52 MB file. The suite runs here with a private
# TMPDIR, and that folder must be empty when the suite ends.
LEFT="$(mktemp -d "${TMPDIR:-/tmp}/test-lib-fresh-home.XXXXXX")"
TMPDIR="$LEFT" "$BASH" "$REPO_DIR/tests/test-maintenance-check.sh" >/dev/null 2>&1
rc=$?
assert_eq "4.1 the maintenance suite passes" 0 "$rc"
assert_eq "4.2 it leaves nothing in TMPDIR" "" "$(ls -A "$LEFT")"
rm -rf "$LEFT"

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo
[ "$FAIL" -eq 0 ]
