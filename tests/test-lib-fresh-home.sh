#!/usr/bin/env bash
# tests/test-lib-fresh-home.sh -- verify tests/lib/fresh-home.sh builds a throwaway HOME
# whose ~/.claude links point at the repo under test, and never touches the real HOME.
# ~/.claude/memory is a real folder with a fixture index, as install.sh leaves it.
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

# The helper homes live in their own parent folder. The parent exists before the snapshot, so a
# TMPDIR that equals HOME cannot change the listing that case 3.3 compares.
PARENT="$(mktemp -d "${TMPDIR:-/tmp}/test-lib-fresh-home.XXXXXX")" || exit 1
# A relative TMPDIR gives a relative PARENT, and the cd in section 2b would change what it names.
PARENT="$(CDPATH='' cd -- "$PARENT" && pwd)" || exit 1
REAL_HOME_BEFORE="$(find "$HOME" -maxdepth 1 | sort | cksum)"

H1="$(TMPDIR="$PARENT" fresh_home_new "$REPO_DIR")"
H2="$(TMPDIR="$PARENT" fresh_home_new "$REPO_DIR")"
trap 'rm -rf "$PARENT"' EXIT

echo "--- 1. the folder"
assert_eq "1.1 first HOME is a folder" yes "$(yesno test -d "$H1")"
assert_eq "1.2 two calls return two different folders" yes "$(yesno test "$H1" != "$H2")"
assert_eq "1.3 the folder is not the real HOME" yes "$(yesno test "$H1" != "$HOME")"

echo "--- 2. the links point at the repo under test"
for name in hooks scripts rules commands skills agents; do
	assert_eq "2.$name link target" "$REPO_DIR/claude/$name" "$(readlink "$H1/.claude/$name")"
	assert_eq "2.$name link resolves to a folder" yes "$(yesno test -d "$H1/.claude/$name/")"
done
assert_eq "2.memory is not a link" no "$(yesno test -L "$H1/.claude/memory")"
assert_eq "2.memory is a real folder" yes "$(yesno test -d "$H1/.claude/memory")"
assert_eq "2.memory holds a MEMORY.md index" yes "$(yesno test -f "$H1/.claude/memory/MEMORY.md")"

echo "--- 2b. a relative repo path still gives working links"
# A relative target would resolve against $home/.claude and the links would dangle.
H3="$(cd "$REPO_DIR/.." && TMPDIR="$PARENT" fresh_home_new "$(basename "$REPO_DIR")")"
assert_eq "2b.1 a relative name gives an absolute link target" "$REPO_DIR/claude/hooks" "$(readlink "$H3/.claude/hooks")"
assert_eq "2b.2 that link resolves to a folder" yes "$(yesno test -d "$H3/.claude/hooks/")"
H4="$(cd "$REPO_DIR" && TMPDIR="$PARENT" fresh_home_new .)"
assert_eq "2b.3 a dot path gives an absolute link target" "$REPO_DIR/claude/scripts" "$(readlink "$H4/.claude/scripts")"
assert_eq "2b.4 that link resolves to a folder" yes "$(yesno test -d "$H4/.claude/scripts/")"
BEFORE_COUNT="$(find "$PARENT" -maxdepth 1 | wc -l | tr -d ' ')"
TMPDIR="$PARENT" fresh_home_new "$PARENT/no-such-folder" >/dev/null 2>&1
assert_eq "2b.5 a repo path that does not exist fails" 1 "$?"
assert_eq "2b.6 a failed call leaves no folder behind" "$BEFORE_COUNT" "$(find "$PARENT" -maxdepth 1 | wc -l | tr -d ' ')"

echo "--- 2c. CDPATH does not change which repo a relative path names"
# A CDPATH entry that holds a same-named folder wins over the current folder, and cd then prints
# the path it chose. The helper must ignore CDPATH.
mkdir -p "$PARENT/decoy/$(basename "$REPO_DIR")"
H5="$(cd "$REPO_DIR/.." && CDPATH="$PARENT/decoy" TMPDIR="$PARENT" fresh_home_new "$(basename "$REPO_DIR")")"
assert_eq "2c.1 the link target is the repo in the current folder, on one line" "$REPO_DIR/claude/hooks" "$(readlink "$H5/.claude/hooks")"

echo "--- 3. what the helper must leave alone"
assert_eq "3.1 plans folder is absent (fresh machine state)" no "$(yesno test -e "$H1/.claude/plans")"
assert_eq "3.2 projects folder is absent (fresh machine state)" no "$(yesno test -e "$H1/.claude/projects")"
assert_eq "3.3 real HOME listing is unchanged" "$REAL_HOME_BEFORE" "$(find "$HOME" -maxdepth 1 | sort | cksum)"

if [ -z "${FRESH_HOME_INNER:-}" ]; then
	echo "--- 4. the suite keeps its scratch folder absolute and stops when it cannot make one"
	# Run this suite again in a child. A relative TMPDIR must not break it. A TMPDIR that mktemp
	# cannot use must stop it before any home exists; a fallback to /tmp would leave homes behind.
	(cd "$PARENT" && FRESH_HOME_INNER=1 TMPDIR=. bash "$REPO_DIR/tests/test-lib-fresh-home.sh" >/dev/null 2>&1)
	assert_eq "4.1 a relative TMPDIR still passes" 0 "$?"
	FRESH_HOME_INNER=1 TMPDIR=/no/such/folder bash "$REPO_DIR/tests/test-lib-fresh-home.sh" >/dev/null 2>&1
	assert_eq "4.2 an unusable TMPDIR stops the suite" 1 "$?"

	echo "--- 5. a suite that builds HOMEs with the helper removes them at exit"
	# Why: test-maintenance-check.sh once built each HOME inside $(...). The subshell lost the list of
	# HOMEs, so every run left them behind, one with a 52 MB file. The suite runs here with a private
	# TMPDIR inside the absolute $PARENT, and that folder must be empty when the suite ends.
	LEFT="$(mktemp -d "$PARENT/maintenance.XXXXXX")" || exit 1
	TMPDIR="$LEFT" "$BASH" "$REPO_DIR/tests/test-maintenance-check.sh" >/dev/null 2>&1
	rc=$?
	assert_eq "5.1 the maintenance suite passes" 0 "$rc"
	assert_eq "5.2 it leaves nothing in TMPDIR" "" "$(ls -A "$LEFT")"
fi

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo
[ "$FAIL" -eq 0 ]
