#!/usr/bin/env bash
# tests/run-all.sh -- run the full test suite
#
# Exits 0 if all tests pass; non-zero if any fail.

set -u

# When run via git pre-commit, git sets GIT_DIR/GIT_WORK_TREE which causes
# git commands inside test-created temp repos to target the real worktree
# instead of the temp repo. Unset them so each test's isolated git repos
# behave correctly.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

for test_script in "$TESTS_DIR"/test-*.sh; do
	[ -f "$test_script" ] || continue
	name="$(basename "$test_script")"
	echo "=== $name ==="
	if bash "$test_script"; then
		TOTAL_PASS=$((TOTAL_PASS + 1))
	else
		TOTAL_FAIL=$((TOTAL_FAIL + 1))
		FAILED_SUITES+=("$name")
	fi
	echo ""
done

echo "=== Summary ==="
echo "Suites passed: $TOTAL_PASS"
echo "Suites failed: $TOTAL_FAIL"

if [ "$TOTAL_FAIL" -gt 0 ]; then
	echo "Failed:"
	for s in "${FAILED_SUITES[@]}"; do
		echo "  - $s"
	done
	exit 1
fi

exit 0
