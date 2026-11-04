#!/usr/bin/env bash
# tests/test-lib-cov.sh -- verify tests/lib/cov.sh counts the executed lines of a script.
#
# The fixture tests/fixtures/cov-sample.sh has nine executable lines: two branches, one function,
# and one heredoc. Run with argument "a", eight lines run and the "branch b" echo is missed. Run
# with "b", seven lines run and two are missed. Run both, all nine run. The expected numbers come
# from reading the fixture, not from the helper, so a wrong helper cannot make the test pass.
#
# Usage: bash tests/test-lib-cov.sh
# On bash older than 4.1 the tracing cases print SKIP and the suite still passes.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$REPO_DIR/tests/fixtures/cov-sample.sh"

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
# shellcheck source=lib/cov.sh
. "$REPO_DIR/tests/lib/cov.sh"

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/test-lib-cov.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

# Line numbers of the two lines that only one branch runs, read from the fixture itself.
LINE_B="$(grep -n 'echo "branch b"' "$FIXTURE" | cut -d: -f1)"
LINE_HELPER="$(grep -n 'echo "helper"' "$FIXTURE" | cut -d: -f1)"

echo "--- 1. the bash version gate"
SKIPPED="$(
	COV_FAKE_BASH_VERSION=3.2
	cov_begin "$TMPD/old.log"
	cov_report "$FIXTURE"
)"
assert_eq "1.1 bash 3.2 prints one SKIP line and nothing else" "SKIP cov: needs bash 4.1 or later" "$SKIPPED"

if ! cov_enabled; then
	echo "  SKIP  2.x to 5.x tracing needs bash 4.1 or later (this is bash ${BASH_VERSION})"
else
	echo "--- 2. only branch a runs"
	cov_begin "$TMPD/a.log"
	bash "$FIXTURE" a >/dev/null
	cov_end
	REPORT_A="$(COV_VERBOSE=1 cov_report "$FIXTURE")"
	assert_eq "2.1 eight of nine lines hit" "cov: $FIXTURE 8/9 88%" "$(printf '%s\n' "$REPORT_A" | grep '^cov: /')"
	assert_eq "2.2 the missed line is the branch b echo" "cov:   missed: $LINE_B " "$(printf '%s\n' "$REPORT_A" | grep 'missed')"

	echo "--- 3. only branch b runs"
	cov_begin "$TMPD/b.log"
	bash "$FIXTURE" b >/dev/null
	cov_end
	REPORT_B="$(COV_VERBOSE=1 cov_report "$FIXTURE")"
	assert_eq "3.1 seven of nine lines hit" "cov: $FIXTURE 7/9 77%" "$(printf '%s\n' "$REPORT_B" | grep '^cov: /')"
	assert_eq "3.2 the missed lines are branch a and the function body" "cov:   missed: $(printf '%s\n' "$(grep -n 'echo "branch a"' "$FIXTURE" | cut -d: -f1)" "$LINE_HELPER" | sort -n | tr '\n' ' ')" "$(printf '%s\n' "$REPORT_B" | grep 'missed')"

	echo "--- 4. both branches run in one log"
	cov_begin "$TMPD/ab.log"
	bash "$FIXTURE" a >/dev/null
	bash "$FIXTURE" b >/dev/null
	cov_end
	REPORT_AB="$(COV_VERBOSE=1 cov_report "$FIXTURE")"
	assert_eq "4.1 nine of nine lines hit" "cov: $FIXTURE 9/9 100%" "$(printf '%s\n' "$REPORT_AB" | grep '^cov: /')"
	assert_eq "4.2 nothing is missed" "cov:   missed: " "$(printf '%s\n' "$REPORT_AB" | grep 'missed')"

	echo "--- 5. path handling"
	ln -s "$FIXTURE" "$TMPD/link.sh"
	cov_begin "$TMPD/link.log"
	bash "$TMPD/link.sh" a >/dev/null
	cov_end
	assert_eq "5.1 a run through a symlink counts for the real file" "cov: $FIXTURE 8/9 88%" "$(cov_report "$FIXTURE" | grep '^cov: /')"
	cp "$FIXTURE" "$TMPD/never.sh"
	assert_eq "5.2 a script that never ran reports zero hits" "cov: $TMPD/never.sh 0/9 0%" "$(cov_report "$TMPD/never.sh" | grep '^cov: /')"
fi

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo
[ "$FAIL" -eq 0 ]
