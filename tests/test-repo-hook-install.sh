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
INSTALLER="$REPO_DIR/claude/scripts/install-repo-hooks.sh"
ENSURE="$REPO_DIR/claude/hooks/ensure-repo-hooks.sh"

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

# ── 2. Installer on a fresh repo creates both hooks ───────────────────────
# Fail-to-fail: 2.2 fails if install-repo-hooks.sh only handles pre-commit.
echo "# 2. Installer on a fresh repo"
R2="$WORK/r2"
make_repo "$R2"
(cd "$R2" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
assert_eq "2.1 pre-commit hook carries its dispatcher marker" "1" \
	"$(grep -cF 'repo-pre-commit.sh' "$R2/.git/hooks/pre-commit" 2>/dev/null || echo 0)"
assert_eq "2.2 pre-push hook carries its dispatcher marker" "1" \
	"$(grep -cF 'repo-pre-push.sh' "$R2/.git/hooks/pre-push" 2>/dev/null || echo 0)"
assert_eq "2.3 pre-push hook is executable" "1" "$([ -x "$R2/.git/hooks/pre-push" ] && echo 1 || echo 0)"

# ── 3. Pre-commit-only repo gains pre-push; pre-commit untouched ──────────
# Fail-to-fail: 3.1 fails if the installer's early "dispatcher already
# present" exit covers both hooks; 3.2 fails if the pre-push path rewrites
# or migrates the existing pre-commit file; 3.3 fails if a re-run on a repo
# with both hooks does anything but report them present.
echo "# 3. Existing pre-commit-only repo"
R3="$WORK/r3"
make_repo "$R3"
printf '#!/usr/bin/env bash\n# repo-specific guard kept by the migration\necho custom-guard\nbash "$HOME/.claude/hooks/repo-pre-commit.sh"\n' >"$R3/.git/hooks/pre-commit"
chmod +x "$R3/.git/hooks/pre-commit"
BEFORE=$(shasum "$R3/.git/hooks/pre-commit" | cut -d' ' -f1)
(cd "$R3" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
assert_eq "3.1 pre-push hook added alongside an existing pre-commit" "1" \
	"$(grep -cF 'repo-pre-push.sh' "$R3/.git/hooks/pre-push" 2>/dev/null || echo 0)"
assert_eq "3.2 existing pre-commit hook is byte-identical after re-run" "$BEFORE" \
	"$(shasum "$R3/.git/hooks/pre-commit" | cut -d' ' -f1)"
RERUN=$(cd "$R3" && HOME="$TMP_HOME" bash "$INSTALLER" 2>&1)
assert_eq "3.3 re-run with both hooks present reports ok twice" "2" "$(printf '%s\n' "$RERUN" | grep -c '^  ok ')"

# ── 4. ensure-repo-hooks.sh installs a missing pre-push ───────────────────
# Fail-to-fail: 4.1 fails if ensure-repo-hooks.sh exits early on the
# pre-commit marker alone (every repo on a dev machine already has it, so
# no existing repo would ever receive pre-push).
echo "# 4. Auto-installer on a pre-commit-only repo"
R4="$WORK/r4"
make_repo "$R4"
printf '#!/usr/bin/env bash\nbash "$HOME/.claude/hooks/repo-pre-commit.sh"\n' >"$R4/.git/hooks/pre-commit"
chmod +x "$R4/.git/hooks/pre-commit"
(cd "$R4" && HOME="$TMP_HOME" bash "$ENSURE" >/dev/null 2>&1)
assert_eq "4.1 ensure-repo-hooks installs pre-push when only pre-commit exists" "1" \
	"$(grep -cF 'repo-pre-push.sh' "$R4/.git/hooks/pre-push" 2>/dev/null || echo 0)"
ENSURE_OUT=$(cd "$R4" && HOME="$TMP_HOME" bash "$ENSURE" 2>&1)
assert_eq "4.2 ensure-repo-hooks is silent once both hooks exist" "" "$ENSURE_OUT"

# ── 5. Pre-existing hooks without the execute bit become executable ───────
# git silently skips a hook file that is not executable, so an installer
# that reports "ok" or "updated" on such a file leaves a hook that never
# runs. Fail-to-fail: 5.1 fails if the "dispatcher already present" branch
# omits chmod +x; 5.2 fails if the "appended dispatcher" branch omits it.
echo "# 5. Non-executable pre-existing hooks"
R5="$WORK/r5"
make_repo "$R5"
printf '#!/usr/bin/env bash\nbash "$HOME/.claude/hooks/repo-pre-commit.sh"\n' >"$R5/.git/hooks/pre-commit"
printf '#!/usr/bin/env bash\necho custom-push-guard\n' >"$R5/.git/hooks/pre-push"
chmod -x "$R5/.git/hooks/pre-commit" "$R5/.git/hooks/pre-push"
(cd "$R5" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
assert_eq "5.1 marker-present pre-commit hook is executable after re-run" "1" \
	"$([ -x "$R5/.git/hooks/pre-commit" ] && echo 1 || echo 0)"
assert_eq "5.2 appended-to pre-push hook is executable after re-run" "1" \
	"$([ -x "$R5/.git/hooks/pre-push" ] && echo 1 || echo 0)"

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "test-repo-hook-install: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
