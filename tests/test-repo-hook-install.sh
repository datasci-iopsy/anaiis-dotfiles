#!/usr/bin/env bash
# tests/test-repo-hook-install.sh -- the repo hook dispatchers and their
# installer: which git stage runs the full test suite, and whether
# install-repo-hooks.sh / ensure-repo-hooks.sh put all three hooks in place
# (pre-commit, pre-push, commit-msg), in a plain repo, a linked worktree, and a
# repo with core.hooksPath.
#
# Contract under test (issue #12): commits run only the staged-file linters;
# the full tests/run-all.sh run happens at pre-push. Every repo that already
# has the pre-commit dispatcher must gain the pre-push and commit-msg ones on
# re-run. The commit-msg lint itself is tested in test-commit-msg-lint.sh.
#
# Hermetic: dispatchers resolve their scripts through $HOME/.claude, so each
# case runs with HOME pointed at a throwaway tree whose .claude/{scripts,hooks}
# link into this repo. Fixture repos live under mktemp and carry a stub
# tests/run-all.sh that drops a sentinel file when executed.
#
# Exit 0 on full pass; non-zero on any failure.

# SC2016: single quotes hold literal "$HOME" and "$1" hook text on purpose.
# shellcheck disable=SC2016
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

# Throwaway HOME whose ~/.claude links point at this checkout (F0 helper).
. "$REPO_DIR/tests/lib/fresh-home.sh"
TMP_HOME="$(TMPDIR="$WORK" fresh_home_new "$REPO_DIR")"

# Opt-in line coverage: COV=1 bash tests/test-repo-hook-install.sh (needs bash 4.1 or later).
if [ -n "${COV:-}" ]; then
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$WORK/cov.log"
fi

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

# Ref lines in the format git writes to pre-push's stdin:
# "<local ref> <local sha> <remote ref> <remote sha>". A local sha of all
# zeros is a branch deletion; an empty stdin is a push with nothing to send.
SHA_A=1111111111111111111111111111111111111111
SHA_B=2222222222222222222222222222222222222222
ZERO=0000000000000000000000000000000000000000
PUSH_LINE="refs/heads/main $SHA_A refs/heads/main $SHA_B"
DELETE_LINE="(delete) $ZERO refs/heads/old $SHA_B"

# ── 1. Which dispatcher runs the suite ────────────────────────────────────
# Fail-to-fail: 1.1 fails if the run-all block stays in repo-pre-commit.sh;
# 1.2 fails if repo-pre-push.sh is missing or omits the block; 1.4 fails if
# the empty-stdin early exit is removed (git still invokes pre-push on a
# no-op push, so the suite would run before "Everything up-to-date"); 1.5
# fails if the zero-sha deletion check is removed.
echo "# 1. Dispatcher responsibilities"
R1="$WORK/r1"
make_repo "$R1"
(cd "$R1" && HOME="$TMP_HOME" bash "$PRE_COMMIT" >/dev/null 2>&1)
assert_eq "1.1 pre-commit dispatcher does not run tests/run-all.sh" "0" "$(exists "$R1/.suite-ran")"
rm -f "$R1/.suite-ran"
(cd "$R1" && printf '%s\n' "$PUSH_LINE" | HOME="$TMP_HOME" bash "$PRE_PUSH" >/dev/null 2>&1)
assert_eq "1.2 pre-push dispatcher runs tests/run-all.sh when a ref sends commits" "1" "$(exists "$R1/.suite-ran")"
rm -f "$R1/.suite-ran"
(cd "$R1" && printf '%s\n' "$PUSH_LINE" | SKIP_TESTS=1 HOME="$TMP_HOME" bash "$PRE_PUSH" >/dev/null 2>&1)
assert_eq "1.3 SKIP_TESTS=1 bypasses the pre-push suite run" "0" "$(exists "$R1/.suite-ran")"
rm -f "$R1/.suite-ran"
(cd "$R1" && printf '' | HOME="$TMP_HOME" bash "$PRE_PUSH" >/dev/null 2>&1)
assert_eq "1.4 empty ref list (nothing to push) does not run the suite" "0" "$(exists "$R1/.suite-ran")"
rm -f "$R1/.suite-ran"
(cd "$R1" && printf '%s\n' "$DELETE_LINE" | HOME="$TMP_HOME" bash "$PRE_PUSH" >/dev/null 2>&1)
assert_eq "1.5 deletion-only push does not run the suite" "0" "$(exists "$R1/.suite-ran")"
rm -f "$R1/.suite-ran"
(cd "$R1" && printf '%s\n%s\n' "$DELETE_LINE" "$PUSH_LINE" | HOME="$TMP_HOME" bash "$PRE_PUSH" >/dev/null 2>&1)
assert_eq "1.6 deletion plus a ref that sends commits still runs the suite" "1" "$(exists "$R1/.suite-ran")"

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
# The commit-msg hook (opt-in lint) is the third dispatcher. Fail-to-fail: 2.4
# fails if the installer omits the hook or writes another line; 2.5 fails if
# it skips chmod +x.
assert_eq "2.4 commit-msg hook carries its dispatcher line, passing the message file" "1" \
	"$(grep -cFx 'bash "$HOME/.claude/hooks/repo-commit-msg.sh" "$1"' "$R2/.git/hooks/commit-msg" 2>/dev/null || echo 0)"
assert_eq "2.5 commit-msg hook is executable" "1" "$([ -x "$R2/.git/hooks/commit-msg" ] && echo 1 || echo 0)"

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
assert_eq "3.3 re-run with all three hooks present reports ok three times" "3" "$(printf '%s\n' "$RERUN" | grep -c '^  ok ')"
assert_eq "3.4 commit-msg hook added alongside an existing pre-commit" "1" \
	"$(grep -cF 'repo-commit-msg.sh' "$R3/.git/hooks/commit-msg" 2>/dev/null || echo 0)"

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
# The same two paths for commit-msg, plus: an existing custom commit-msg hook
# keeps its own lines when the dispatcher line is appended. Fail-to-fail: 5.3
# fails if the marker-present branch omits chmod +x; 5.4 fails if the append
# branch replaces the file or drops the dispatcher.
R5B="$WORK/r5b"
make_repo "$R5B"
printf '#!/usr/bin/env bash\nbash "$HOME/.claude/hooks/repo-commit-msg.sh" "$1"\n' >"$R5B/.git/hooks/commit-msg"
chmod -x "$R5B/.git/hooks/commit-msg"
(cd "$R5B" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
assert_eq "5.3 marker-present commit-msg hook is executable after re-run" "1" \
	"$([ -x "$R5B/.git/hooks/commit-msg" ] && echo 1 || echo 0)"
R5C="$WORK/r5c"
make_repo "$R5C"
printf '#!/usr/bin/env bash\necho custom-msg-guard\n' >"$R5C/.git/hooks/commit-msg"
chmod +x "$R5C/.git/hooks/commit-msg"
(cd "$R5C" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
assert_eq "5.4 custom commit-msg hook keeps its line and gains the dispatcher" "1 1" \
	"$(grep -cF 'echo custom-msg-guard' "$R5C/.git/hooks/commit-msg") $(grep -cF 'repo-commit-msg.sh' "$R5C/.git/hooks/commit-msg")"

# ── 6. Installer from a linked worktree ───────────────────────────────────
# In a linked worktree, `.git` is a file and `git rev-parse --git-dir` names a
# per-worktree folder that has no hooks folder. Git itself runs the hooks of
# the common folder. Fail-to-fail: 6.1 and 6.2 fail if the installer builds the
# hooks path from --git-dir; 6.5 fails if it exits 0 on a non-repo folder.
echo "# 6. Installer from a linked worktree"
R6="$WORK/r6"
W6="$WORK/w6"
make_repo "$R6"
git -C "$R6" worktree add -q -b wt6 "$W6"
(cd "$W6" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
RC6=$?
assert_eq "6.1 installer exits 0 from a linked worktree" "0" "$RC6"
assert_eq "6.2 pre-commit hook lands in the common hooks folder" "1" \
	"$(grep -cF 'repo-pre-commit.sh' "$R6/.git/hooks/pre-commit" 2>/dev/null || echo 0)"
assert_eq "6.3 pre-push hook lands in the common hooks folder" "1" \
	"$(grep -cF 'repo-pre-push.sh' "$R6/.git/hooks/pre-push" 2>/dev/null || echo 0)"
BEFORE6=$(shasum "$R6/.git/hooks/pre-commit" "$R6/.git/hooks/pre-push" "$R6/.git/hooks/commit-msg" 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')
RERUN6=$(cd "$W6" && HOME="$TMP_HOME" bash "$INSTALLER" 2>&1)
assert_eq "6.4 second run from the worktree reports ok three times and changes nothing" "3 $BEFORE6" \
	"$(printf '%s\n' "$RERUN6" | grep -c '^  ok ') $(shasum "$R6/.git/hooks/pre-commit" "$R6/.git/hooks/pre-push" "$R6/.git/hooks/commit-msg" | cut -d' ' -f1 | tr '\n' ' ')"
mkdir -p "$WORK/norepo"
NOREPO_OUT=$(cd "$WORK/norepo" && GIT_CEILING_DIRECTORIES="$WORK" HOME="$TMP_HOME" bash "$INSTALLER" 2>&1)
NOREPO_RC=$?
assert_eq "6.5 outside a git repo the installer exits 1 with its error text" "1 ERROR: not inside a git repository." \
	"$NOREPO_RC $NOREPO_OUT"
# The hook path in the report is absolute even from a sub folder.
R6B="$WORK/r6b"
make_repo "$R6B"
mkdir -p "$R6B/sub"
SUB_LINE=$(cd "$R6B/sub" && HOME="$TMP_HOME" bash "$INSTALLER" 2>&1 | sed -n '1p')
case "$SUB_LINE" in
	"  created  /"*) SUB_ABS=1 ;;
	*) SUB_ABS=0 ;;
esac
assert_eq "6.6 installer report names an absolute hook path from a sub folder" "1" "$SUB_ABS"

# ── 7. Auto-installer from a linked worktree ──────────────────────────────
# Fail-to-fail: 7.1 and 7.2 fail if ensure-repo-hooks.sh reads $repo/.git/hooks
# (a file path in a worktree); 7.4 fails if it never detects the wired hooks.
echo "# 7. Auto-installer from a linked worktree"
R7="$WORK/r7"
W7="$WORK/w7"
make_repo "$R7"
git -C "$R7" worktree add -q -b wt7 "$W7"
ERR7=$(cd "$W7" && HOME="$TMP_HOME" bash "$ENSURE" 2>&1 >/dev/null)
RC7=$?
assert_eq "7.1 ensure-repo-hooks exits 0 with empty stderr from a worktree" "0 " "$RC7 $ERR7"
assert_eq "7.2 ensure-repo-hooks wired all three hooks in the common folder" "1 1 1" \
	"$(grep -cF 'repo-pre-commit.sh' "$R7/.git/hooks/pre-commit" 2>/dev/null || echo 0) $(grep -cF 'repo-pre-push.sh' "$R7/.git/hooks/pre-push" 2>/dev/null || echo 0) $(grep -cF 'repo-commit-msg.sh' "$R7/.git/hooks/commit-msg" 2>/dev/null || echo 0)"
# Second run with a HOME that has no installer: a silent run proves the early exit.
ERR7B=$(cd "$W7" && HOME="$WORK/no-such-home" bash "$ENSURE" 2>&1 >/dev/null)
assert_eq "7.3 second run from the worktree exits before it calls the installer" "" "$ERR7B"
# Same check from a sub folder of the worktree.
mkdir -p "$W7/sub"
ERR7C=$(cd "$W7/sub" && HOME="$WORK/no-such-home" bash "$ENSURE" 2>&1 >/dev/null)
assert_eq "7.4 the early exit also holds from a sub folder of the worktree" "" "$ERR7C"
# In a normal repo git prints a path relative to the repo root (`.git/hooks`).
R7B="$WORK/r7b"
make_repo "$R7B"
mkdir -p "$R7B/sub"
(cd "$R7B/sub" && HOME="$TMP_HOME" bash "$ENSURE" >/dev/null 2>&1)
ERR7D=$(cd "$R7B/sub" && HOME="$WORK/no-such-home" bash "$ENSURE" 2>&1 >/dev/null)
assert_eq "7.5 the early exit holds from a sub folder of a normal repo" "" "$ERR7D"

# ── 8. core.hooksPath is honored ──────────────────────────────────────────
# Git ignores .git/hooks when core.hooksPath is set. Fail-to-fail: 8.1 fails if
# the installer writes to .git/hooks; 8.2 fails if a relative path is not made
# absolute (git runs hooks from the top of the working tree).
echo "# 8. core.hooksPath"
R8="$WORK/r8"
make_repo "$R8"
git -C "$R8" config core.hooksPath "$WORK/custom-hooks"
(cd "$R8" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
assert_eq "8.1 absolute core.hooksPath receives both hooks (folder created)" "1 1" \
	"$(grep -cF 'repo-pre-commit.sh' "$WORK/custom-hooks/pre-commit" 2>/dev/null || echo 0) $(grep -cF 'repo-pre-push.sh' "$WORK/custom-hooks/pre-push" 2>/dev/null || echo 0)"
R9="$WORK/r9"
make_repo "$R9"
git -C "$R9" config core.hooksPath rel-hooks
mkdir -p "$R9/sub"
(cd "$R9/sub" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
assert_eq "8.2 relative core.hooksPath resolves from the top of the working tree" "1" \
	"$(grep -cF 'repo-pre-commit.sh' "$R9/rel-hooks/pre-commit" 2>/dev/null || echo 0)"

# ── 9. Audit agrees with the installer ────────────────────────────────────
# maintenance-check.sh counts audit lines that start with STALE, missing, or
# absent. A repo that the installer wired must read as ok, or the user gets a
# warning that no action can clear. Fail-to-fail: 9.1 fails if the audit reads
# $git_dir/hooks instead of asking git; 9.2 fails if the audit does not make
# git's relative path absolute. 9.2 also pins the decision that the audit needs
# no worktree logic: a linked worktree has a `.git` file, so find skips it.
echo "# 9. Audit"
AUDIT="$REPO_DIR/claude/scripts/audit-repo-hooks.sh"
AUDIT_DIR="$WORK/auditdir"
mkdir -p "$AUDIT_DIR"
make_repo "$AUDIT_DIR/hp"
git -C "$AUDIT_DIR/hp" config core.hooksPath "$WORK/audit-hooks"
(cd "$AUDIT_DIR/hp" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
# Run the audit from a neutral folder, so a relative hooks path cannot match the caller's repo.
AUDIT_OUT=$(cd "$WORK" && HOOK_SEARCH_DIRS="$AUDIT_DIR" bash "$AUDIT" 2>&1)
assert_eq "9.1 audit reports a core.hooksPath repo as ok after install" "1" \
	"$(printf '%s\n' "$AUDIT_OUT" | grep -c '^  ok ')"
AUDIT_DIR2="$WORK/auditdir2"
mkdir -p "$AUDIT_DIR2"
make_repo "$AUDIT_DIR2/wt-main"
git -C "$AUDIT_DIR2/wt-main" worktree add -q -b wt9 "$AUDIT_DIR2/wt-linked"
(cd "$AUDIT_DIR2/wt-main" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
AUDIT_OUT=$(cd "$WORK" && HOOK_SEARCH_DIRS="$AUDIT_DIR2" bash "$AUDIT" 2>&1)
assert_eq "9.2 audit counts a repo with a linked worktree once" "1 0" \
	"$(printf '%s\n' "$AUDIT_OUT" | grep -c '^  ok ') $(printf '%s\n' "$AUDIT_OUT" | grep -c 'wt-linked')"

AUDIT_DIR3="$WORK/auditdir3"
mkdir -p "$AUDIT_DIR3"
make_repo "$AUDIT_DIR3/no-msg"
printf '#!/usr/bin/env bash\nbash "$HOME/.claude/hooks/repo-pre-commit.sh"\n' >"$AUDIT_DIR3/no-msg/.git/hooks/pre-commit"
printf '#!/usr/bin/env bash\nbash "$HOME/.claude/hooks/repo-pre-push.sh"\n' >"$AUDIT_DIR3/no-msg/.git/hooks/pre-push"
AUDIT_OUT=$(cd "$WORK" && HOOK_SEARCH_DIRS="$AUDIT_DIR3" bash "$AUDIT" 2>&1)
AUDIT_RC=$?
assert_eq "9.3 audit flags a repo that lacks the commit-msg hook (line starts with 'missing')" "1 1" \
	"$AUDIT_RC $(printf '%s\n' "$AUDIT_OUT" | grep -cE '^[[:space:]]*missing ')"
(cd "$AUDIT_DIR3/no-msg" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
AUDIT_OUT=$(cd "$WORK" && HOOK_SEARCH_DIRS="$AUDIT_DIR3" bash "$AUDIT" 2>&1)
AUDIT_RC=$?
assert_eq "9.4 audit reports the same repo ok once the installer added commit-msg" "0 1" \
	"$AUDIT_RC $(printf '%s\n' "$AUDIT_OUT" | grep -c '^  ok ')"

# ── 10. Existing repos receive the commit-msg hook ────────────────────────
# A repo that already has pre-commit and pre-push (every repo set up before the
# lint existed) must gain commit-msg from the auto-installer. Fail-to-fail: 10.1
# fails if ensure-repo-hooks.sh leaves its early exit at two markers.
echo "# 10. Auto-installer on a repo with pre-commit and pre-push"
R10="$WORK/r10"
make_repo "$R10"
printf '#!/usr/bin/env bash\nbash "$HOME/.claude/hooks/repo-pre-commit.sh"\n' >"$R10/.git/hooks/pre-commit"
printf '#!/usr/bin/env bash\nbash "$HOME/.claude/hooks/repo-pre-push.sh"\n' >"$R10/.git/hooks/pre-push"
chmod +x "$R10/.git/hooks/pre-commit" "$R10/.git/hooks/pre-push"
(cd "$R10" && HOME="$TMP_HOME" bash "$ENSURE" >/dev/null 2>&1)
assert_eq "10.1 ensure-repo-hooks installs commit-msg when the other two exist" "1" \
	"$(grep -cF 'repo-commit-msg.sh' "$R10/.git/hooks/commit-msg" 2>/dev/null || echo 0)"

# ── Summary ───────────────────────────────────────────────────────────────
if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$INSTALLER" "$ENSURE" "$AUDIT"
fi
echo
echo "test-repo-hook-install: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
