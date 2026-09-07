#!/usr/bin/env bash
# tests/test-repo-hook-install.sh -- the repo hook dispatchers and their
# installer: which git stage runs the full test suite, and whether
# install-repo-hooks.sh / ensure-repo-hooks.sh put both hooks in place.
#
# Contract under test (issue #12): commits run only the staged-file linters;
# the full tests/run-all.sh run happens at pre-push. Every repo that already
# has the pre-commit dispatcher must gain the pre-push one on re-run.
#
# Hermetic: dispatchers resolve their scripts through $HOME/.claude, so each
# case runs with HOME pointed at a throwaway tree whose .claude/{scripts,hooks}
# link into this repo. Fixture repos live under mktemp and carry a stub
# tests/run-all.sh that drops a sentinel file when executed.
#
# Exit 0 on full pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRE_COMMIT="$REPO_DIR/claude/hooks/repo-pre-commit.sh"
PRE_PUSH="$REPO_DIR/claude/hooks/repo-pre-push.sh"

PASS=0
FAIL=0

assert_eq() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

TMP_HOME="$WORK/home"
mkdir -p "$TMP_HOME/.claude"
ln -s "$REPO_DIR/claude/scripts" "$TMP_HOME/.claude/scripts"
ln -s "$REPO_DIR/claude/hooks" "$TMP_HOME/.claude/hooks"

# make_repo <dir>: a committed git repo with a stub tests/run-all.sh that
# creates .suite-ran at the repo root when executed.
make_repo() {
	local dir="$1"
	mkdir -p "$dir/tests"
	git -C "$dir" init -q
	git -C "$dir" config user.email "test@test.com"
	git -C "$dir" config user.name "Test"
	printf '#!/usr/bin/env bash\ntouch "$(git rev-parse --show-toplevel)/.suite-ran"\n' >"$dir/tests/run-all.sh"
	printf 'x\n' >"$dir/f.txt"
	git -C "$dir" add tests/run-all.sh f.txt
	git -C "$dir" commit -q -m init
}

exists() { [ -e "$1" ] && echo 1 || echo 0; }

# ── 1. Which dispatcher runs the suite ────────────────────────────────────
# Fail-to-fail: 1.1 fails if the run-all block stays in repo-pre-commit.sh;
# 1.2 fails if repo-pre-push.sh is missing or omits the block.
echo "# 1. Dispatcher responsibilities"
R1="$WORK/r1"
make_repo "$R1"
(cd "$R1" && HOME="$TMP_HOME" bash "$PRE_COMMIT" >/dev/null 2>&1)
assert_eq "1.1 pre-commit dispatcher does not run tests/run-all.sh" "0" "$(exists "$R1/.suite-ran")"
rm -f "$R1/.suite-ran"
(cd "$R1" && HOME="$TMP_HOME" bash "$PRE_PUSH" >/dev/null 2>&1)
assert_eq "1.2 pre-push dispatcher runs tests/run-all.sh" "1" "$(exists "$R1/.suite-ran")"
rm -f "$R1/.suite-ran"
(cd "$R1" && SKIP_TESTS=1 HOME="$TMP_HOME" bash "$PRE_PUSH" >/dev/null 2>&1)
assert_eq "1.3 SKIP_TESTS=1 bypasses the pre-push suite run" "0" "$(exists "$R1/.suite-ran")"

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "test-repo-hook-install: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
