#!/usr/bin/env bash
# tests/test-maintenance-check.sh -- verify claude/hooks/maintenance-check.sh on a fresh machine.
#
# Why this matters: the hook runs on every prompt. On a fresh HOME there is no ~/.claude/plans folder.
# `find` then fails, `set -o pipefail` carries the failure out of the `$(...)` pipeline, and `set -e`
# ends the script with exit 1 before it writes any stamp. The hook then fails on every prompt.
#
# The suite runs the hook only against throwaway HOMEs built by tests/lib/fresh-home.sh. It never
# reads or writes the real HOME.
#
# Env override, used for the fail-to-fail check:
#   HOOK   path of the hook under test
#
# Usage: bash tests/test-maintenance-check.sh        (COV=1 adds line coverage on bash 4.1 or later)

set -u
unset HOOK_SEARCH_DIRS

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK:-$REPO_DIR/claude/hooks/maintenance-check.sh}"
CLEAN_PLANS="$REPO_DIR/claude/scripts/clean-plans.sh"

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

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/fresh-home.sh
. "$REPO_DIR/tests/lib/fresh-home.sh"

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/test-maintenance-check.XXXXXX")"
HOMES=""
trap 'rm -rf "$TMPD" $HOMES' EXIT

if [ -n "${COV:-}" ]; then
	# shellcheck source-path=SCRIPTDIR
	# shellcheck source=lib/cov.sh
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$TMPD/cov.log"
fi

new_home() {
	local h
	h="$(fresh_home_new "$REPO_DIR")"
	HOMES="$HOMES $h"
	printf '%s\n' "$h"
}

# Run the hook against HOME $1. Standard error goes to $TMPD/err; the exit code is in RC.
run_hook() {
	HOME="$1" bash "$HOOK" 2>"$TMPD/err" >/dev/null
	RC=$?
	ERR="$(cat "$TMPD/err")"
}

# Make N plan files in HOME $1.
make_plans() {
	local i=1
	mkdir -p "$1/.claude/plans"
	while [ "$i" -le "$2" ]; do
		: >"$1/.claude/plans/plan-$i.md"
		i=$((i + 1))
	done
}

# Make every stamp in HOME $1 look ten days old, so the weekly checks run again.
age_stamps() {
	local s
	for s in plans hooks; do
		printf '1970-01-01\n' >"$1/.claude/.maintenance-$s"
	done
}

yesno() {
	if "$@"; then echo yes; else echo no; fi
}

echo "--- 1. fresh HOME: no plans folder, no projects folder"
H1="$(new_home)"
run_hook "$H1"
assert_eq "1.1 exit code is 0" 0 "$RC"
assert_eq "1.2 standard error is empty" "" "$ERR"
assert_eq "1.3 plans stamp is written" yes "$(yesno test -s "$H1/.claude/.maintenance-plans")"
assert_eq "1.4 sessions stamp is written" yes "$(yesno test -s "$H1/.claude/.maintenance-sessions")"
assert_eq "1.5 hooks stamp is written" yes "$(yesno test -s "$H1/.claude/.maintenance-hooks")"
assert_eq "1.6 the hook did not create a plans folder" no "$(yesno test -e "$H1/.claude/plans")"

echo "--- 2. the second run does not scan again"
make_plans "$H1" 11
STAMP_BEFORE="$(cat "$H1/.claude/.maintenance-plans")"
run_hook "$H1"
assert_eq "2.1 exit code is 0" 0 "$RC"
assert_eq "2.2 11 new plan files stay unreported while the stamp is fresh" "" "$ERR"
assert_eq "2.3 plans stamp is unchanged" "$STAMP_BEFORE" "$(cat "$H1/.claude/.maintenance-plans")"

echo "--- 3. more than 10 plan files: the message names a real path"
age_stamps "$H1"
run_hook "$H1"
assert_eq "3.1 exit code is 0" 0 "$RC"
case "$ERR" in
	*"Plans: 11 files, 0 older than 14 days -- bash ~/.claude/scripts/clean-plans.sh"*) found=yes ;;
	*) found=no ;;
esac
assert_eq "3.2 stderr reports 11 files and names bash ~/.claude/scripts/clean-plans.sh" yes "$found"
# The path in the message must exist: replace the leading ~ by the throwaway HOME and test it.
named="${ERR##*bash ~/}"
named="${named%%[[:space:]]*}"
assert_eq "3.3 the named script exists under HOME" yes "$(yesno test -f "$H1/$named")"

echo "--- 4. one plan file older than 14 days"
H2="$(new_home)"
make_plans "$H2" 1
touch -t 200001010000 "$H2/.claude/plans/plan-1.md"
run_hook "$H2"
assert_eq "4.1 exit code is 0" 0 "$RC"
case "$ERR" in
	*"Plans: 1 files, 1 older than 14 days"*) found=yes ;;
	*) found=no ;;
esac
assert_eq "4.2 an old file alone triggers the message" yes "$found"

echo "--- 5. plans and projects folders that exist but are empty"
H3="$(new_home)"
make_plans "$H3" 0
mkdir -p "$H3/.claude/projects"
run_hook "$H3"
assert_eq "5.1 exit code is 0" 0 "$RC"
assert_eq "5.2 empty folders stay silent" "" "$ERR"

echo "--- 6. sessions folder over 50 MB"
H4="$(new_home)"
mkdir -p "$H4/.claude/projects"
dd if=/dev/zero of="$H4/.claude/projects/big" bs=1048576 count=52 2>/dev/null
run_hook "$H4"
assert_eq "6.1 exit code is 0" 0 "$RC"
case "$ERR" in
	*"Sessions: "*"MB -- claude-cleanup --older-than 30"*) found=yes ;;
	*) found=no ;;
esac
assert_eq "6.2 a big sessions folder is reported" yes "$found"

echo "--- 7. a repo without a pre-commit hook"
H5="$(new_home)"
mkdir -p "$TMPD/repos"
git init -q --template= "$TMPD/repos/r1"
HOOK_SEARCH_DIRS="$TMPD/repos" run_hook "$H5"
assert_eq "7.1 exit code is 0" 0 "$RC"
# The count in the message is not pinned: the hook also counts the audit summary line, so one repo
# shows as "2 repos" (D-A-06). The test checks that the message appears and names the real script.
case "$ERR" in
	"[maintenance] Repo hooks: "[0-9]*" repos need attention -- bash ~/.claude/scripts/audit-repo-hooks.sh") found=yes ;;
	*) found=no ;;
esac
assert_eq "7.2 the repo is reported" yes "$found"

echo "--- 8. the usage text shows the real path"
assert_eq "8.1 clean-plans.sh usage names ~/.claude/scripts/clean-plans.sh" 1 \
	"$(grep -c '^# Usage: bash ~/.claude/scripts/clean-plans\.sh' "$CLEAN_PLANS" || true)"
assert_eq "8.2 no file still names the old path" 0 \
	"$(grep -c '\.claude/clean-plans\.sh' "$HOOK" "$CLEAN_PLANS" | awk -F: '{s += $NF} END {print s + 0}')"

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$HOOK"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
