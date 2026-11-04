#!/usr/bin/env bash
# tests/test-safe-rm.sh -- verify claude/hooks/safe-rm.sh, the run-time guard for rm.
#
# bash-guard.sh rewrites an eligible compound command so that `rm` is the function in safe-rm.sh.
# The function checks every operand AFTER the shell has expanded it (variables, globs), against
# explicit deletion roots, and deletes nothing unless every operand passes.
#
# Test design: the decision cases put a stub `rm` first on PATH. The stub only logs its arguments.
# A bug in the guard therefore cannot delete anything, not even for an operand like "/". A few
# integration cases then use the real rm inside a throwaway tree and check that files vanish or
# survive. Every case runs in a child shell with a clean environment.
#
# Usage: bash tests/test-safe-rm.sh
#        COV=1 bash tests/test-safe-rm.sh   (line coverage of safe-rm.sh, needs bash 4.1 or later)

# SC2016 is off for the whole file on purpose: each case is a single-quoted snippet that the CHILD
# shell expands ($SCRATCH, $CWD, and so on), not this shell.
# shellcheck disable=SC2016
set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE_RM="$REPO_DIR/claude/hooks/safe-rm.sh"

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

TREE="$(mktemp -d "${TMPDIR:-/tmp}/test-safe-rm.XXXXXX")"
trap 'rm -rf "$TREE"' EXIT

if [ -n "${COV:-}" ]; then
	# shellcheck source-path=SCRIPTDIR
	# shellcheck source=lib/cov.sh
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$TREE/cov.log"
fi

# The fake machine. TREE itself may sit behind a symlink (macOS /var -> /private/var); the guard
# must resolve both sides, so the roots below are passed in their unresolved spelling.
SCRATCH="$TREE/session/scratchpad"
CWD="$TREE/proj"
OUT="$TREE/outside"
TMPR="$TREE/tmpdir"
HOMEF="$TREE/home"
STUB="$TREE/stub"
RMLOG="$TREE/rm.log"
mkdir -p "$SCRATCH" "$CWD/tests/fixtures" "$CWD/tmp/worktrees/wt" "$CWD/node_modules" "$CWD/src" \
	"$CWD/.git" "$OUT" "$TMPR" "$HOMEF" "$STUB"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$RMLOG" >"$STUB/rm"
chmod +x "$STUB/rm"

# child <mode> <snippet>: run the snippet in a clean child shell, in the fake project folder.
#   mode "stub": PATH has the logging stub first. mode "real": PATH has the real rm only.
#   mode "nocwd": like stub, but __SAFE_RM_CWD is unset. mode "noscratch": like stub, scratch unset.
#   mode "cwdscratch": like stub, but the working directory is $SCRATCH/a/b (inside the scratchpad).
# Sets RC, ERR (stderr text), and CALLED (yes when the stub or real rm was reached).
child() {
	local mode="$1" snippet="$2" path_dir="$STUB:/usr/bin:/bin" run_dir="$CWD"
	[ "$mode" = real ] && path_dir="/usr/bin:/bin"
	: >"$RMLOG"
	local scratch_arg="__SAFE_RM_SCRATCH=$SCRATCH" cwd_arg="__SAFE_RM_CWD=$CWD"
	[ "$mode" = noscratch ] && scratch_arg="UNUSED_A=1"
	[ "$mode" = nocwd ] && cwd_arg="UNUSED_B=1"
	if [ "$mode" = cwdscratch ]; then
		mkdir -p "$SCRATCH/a/b"
		run_dir="$SCRATCH/a/b"
		cwd_arg="__SAFE_RM_CWD=$run_dir"
	fi
	# BASH_ENV, BASH_XTRACEFD, and PS4 pass through env -i so that COV=1 can trace the child shell.
	ERR="$(cd "$run_dir" && env -i PATH="$path_dir" HOME="$HOMEF" TMPDIR="$TMPR" "$scratch_arg" "$cwd_arg" \
		BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
		SCRATCH="$SCRATCH" CWD="$CWD" OUT="$OUT" TMPR="$TMPR" HOMEF="$HOMEF" ALIAS="$TREE/alias" SAFE_RM="$SAFE_RM" \
		"$BASH" -c '. "$SAFE_RM"; '"$snippet" 2>&1 >/dev/null)"
	RC=$?
	CALLED=no
	[ -s "$RMLOG" ] && CALLED=yes
	return 0
}

# expect_pass <name> <snippet> [mode]: the guard lets rm run (RC 0, rm reached).
expect_pass() {
	child "${3:-stub}" "$2"
	assert_eq "$1" "rc=0 called=yes" "rc=$RC called=$CALLED"
}

# expect_refuse <name> <snippet> <needle> [mode]: the guard stops rm (RC 1, rm not reached, reason shown).
expect_refuse() {
	child "${4:-stub}" "$2"
	local seen=no
	printf '%s' "$ERR" | grep -qF -- "$3" && seen=yes
	assert_eq "$1" "rc=1 called=no reason=yes" "rc=$RC called=$CALLED reason=$seen"
}

echo "--- 0. loading"
child stub '[ "$(type -t rm)" = function ]'
assert_eq "0.1 sourcing the file defines rm as a function" "rc=0" "rc=$RC"
child stub 'rm -rf "$OUT/f"'
assert_eq "0.2 the function, not the stub, handles the first call" "rc=1 called=no" "rc=$RC called=$CALLED"

echo "--- 1. allowed: the scratchpad"
expect_pass "1.1 file inside the scratchpad" 'rm -rf "$SCRATCH/a"'
expect_pass "1.2 deep path inside the scratchpad" 'rm -rf "$SCRATCH/a/b/c/d"'
ln -s "$TREE" "$TREE/alias"
expect_pass "1.3 scratchpad reached through a symlinked spelling" 'rm -rf "$ALIAS/session/scratchpad/z"'
expect_pass "1.4 a path that does not exist yet (the delete is a no-op)" 'rm -rf "$SCRATCH/not-there"'
expect_pass "1.5 several operands, all inside" 'rm -rf "$SCRATCH/a" "$SCRATCH/b" "$SCRATCH/c"'
expect_pass "1.6 a trailing slash on an ordinary folder" 'mkdir -p "$SCRATCH/dir" && rm -rf "$SCRATCH/dir/"'

echo "--- 2. allowed: disposable folders in the working directory"
expect_pass "2.1 node_modules" 'rm -rf "$CWD/node_modules"'
expect_pass "2.2 a disposable name below another folder" 'rm -rf "$CWD/src/node_modules/x"'
expect_pass "2.3 .venv" 'rm -rf "$CWD/.venv"'
expect_pass "2.4 a file inside dist" 'rm -rf "$CWD/dist/out.js"'
expect_pass "2.5 a relative operand" 'rm -rf node_modules'
expect_pass "2.6 a relative operand with ./" 'rm -rf ./node_modules'
expect_pass "2.7 a folder below tests/fixtures" 'rm -rf "$CWD/tests/fixtures/sub"'
expect_pass "2.8 a folder below tmp" 'rm -rf "$CWD/tmp/scratch"'
expect_pass "2.9 a disposable folder inside a linked worktree" 'rm -rf "$CWD/tmp/worktrees/wt/node_modules"'

echo "--- 3. allowed: mktemp folders"
expect_pass "3.1 a tmp.* folder under TMPDIR" 'rm -rf "$TMPR/tmp.AbC123"'
expect_pass "3.2 a path below a tmp.* folder" 'rm -rf "$TMPR/tmp.AbC123/x/y"'

echo "--- 4. allowed: shell expansion and flag forms"
expect_pass "4.1 -rf" 'rm -rf "$SCRATCH/a"'
expect_pass "4.2 -fr" 'rm -fr "$SCRATCH/a"'
expect_pass "4.3 -Rf" 'rm -Rf "$SCRATCH/a"'
expect_pass "4.4 long flags" 'rm --recursive --force --verbose "$SCRATCH/a"'
expect_pass "4.5 -- before an operand that looks like a flag" 'rm -rf -- "$SCRATCH/-weird"'
expect_pass "4.6 a variable inside a loop" 'for m in a b; do rm -rf "$SCRATCH/ft-$m"; done'
expect_pass "4.7 a glob that expands inside the scratchpad" 'touch "$SCRATCH/g1" "$SCRATCH/g2"; rm -rf "$SCRATCH"/g*'
expect_pass "4.8 no operand: passed on so rm prints its own usage error" 'rm -rf'

echo "--- 5. refused: outside every root"
expect_refuse "5.1 a file outside the roots" 'rm -rf "$OUT/f"' "refused"
expect_refuse "5.2 the root of the file system" 'rm -rf /' "refused"
expect_refuse "5.3 the home folder" 'rm -rf "$HOMEF"' "refused"
expect_refuse "5.4 a path below the home folder" 'rm -rf "$HOMEF/.ssh"' "refused"
expect_refuse "5.5 /tmp itself" 'rm -rf /tmp' "refused"
expect_refuse "5.6 the working directory by name" 'rm -rf .' "refused"
expect_refuse "5.7 the working directory by absolute path" 'rm -rf "$CWD"' "refused"
expect_refuse "5.8 the parent of the working directory (.. component)" 'rm -rf ..' "refused"
expect_refuse "5.9 a source folder in the working directory" 'rm -rf "$CWD/src"' "refused"
expect_refuse "5.10 a .git folder" 'rm -rf "$CWD/.git"' "refused"
expect_refuse "5.11 a .git folder below a disposable folder" 'rm -rf "$CWD/node_modules/.git/x"' "refused"
expect_refuse "5.12 tmp itself" 'rm -rf "$CWD/tmp"' "refused"
expect_refuse "5.13 tmp/worktrees" 'rm -rf "$CWD/tmp/worktrees"' "refused"
expect_refuse "5.14 a linked worktree folder" 'rm -rf "$CWD/tmp/worktrees/wt"' "refused"
expect_refuse "5.15 tests/fixtures itself" 'rm -rf "$CWD/tests/fixtures"' "refused"
expect_refuse "5.16 the scratchpad itself" 'rm -rf "$SCRATCH"' "refused"
expect_refuse "5.17 an .. component inside the scratchpad" 'rm -rf "$SCRATCH/../x"' "refused"
expect_refuse "5.18 TMPDIR itself" 'rm -rf "$TMPR"' "refused"
expect_refuse "5.19 a TMPDIR child that is not tmp.*" 'rm -rf "$TMPR/other"' "refused"
expect_refuse "5.20 tmp. with nothing after the dot" 'rm -rf "$TMPR/tmp."' "refused"
expect_refuse "5.21 an empty operand" 'rm -rf ""' "refused"
expect_refuse "5.22 a variable that is empty" 'rm -rf "$NOPE/x"' "refused"
expect_refuse "5.23 a trailing slash does not hide an outside folder" 'rm -rf "$OUT/"' "refused"

echo "--- 6. refused: flags outside the allowed set"
expect_refuse "6.1 --no-preserve-root" 'rm -rf --no-preserve-root "$SCRATCH/a"' "flag"
expect_refuse "6.2 -x" 'rm -rfx "$SCRATCH/a"' "flag"
expect_refuse "6.3 -i" 'rm -ri "$SCRATCH/a"' "flag"
expect_refuse "6.4 an unknown long flag" 'rm --interactive "$SCRATCH/a"' "flag"

echo "--- 7. refused: one bad operand stops the whole call"
expect_refuse "7.1 good then bad" 'rm -rf "$SCRATCH/a" "$OUT/f"' "refused"
expect_refuse "7.2 bad then good" 'rm -rf "$OUT/f" "$SCRATCH/a"' "refused"

echo "--- 8. fail closed when the hook gave no folder"
expect_refuse "8.1 no working directory: even the scratchpad is refused" 'rm -rf "$SCRATCH/a"' "refused" nocwd
expect_refuse "8.2 no scratchpad: a scratchpad path is refused" 'rm -rf "$SCRATCH/a"' "refused" noscratch
expect_pass "8.3 no scratchpad: a disposable folder still works" 'rm -rf "$CWD/node_modules"' noscratch

echo "--- 8b. the working directory sits inside the scratchpad"
expect_refuse "8b.1 the working directory itself is never deleted" 'rm -rf "$SCRATCH/a/b"' "working directory" cwdscratch
expect_refuse "8b.2 a parent of the working directory is never deleted" 'rm -rf "$SCRATCH/a"' "working directory" cwdscratch
expect_pass "8b.3 a sibling of the working directory is allowed" 'rm -rf "$SCRATCH/a/sibling"' cwdscratch
expect_pass "8b.4 a child of the working directory is allowed" 'rm -rf "$SCRATCH/a/b/child"' cwdscratch

echo "--- 9. real deletes in the throwaway tree"
mkdir -p "$SCRATCH/real/inner" "$OUT/keep"
touch "$SCRATCH/real/inner/f" "$OUT/keep/f"
child real 'rm -rf "$SCRATCH/real"'
assert_eq "9.1 a safe operand is really deleted" "rc=0 gone=yes" "rc=$RC gone=$([ -e "$SCRATCH/real" ] && echo no || echo yes)"

mkdir -p "$SCRATCH/ok2"
touch "$SCRATCH/ok2/f"
child real 'rm -rf "$SCRATCH/ok2" "$OUT/keep"'
assert_eq "9.2 a mixed call deletes nothing" "rc=1 safe_kept=yes unsafe_kept=yes" \
	"rc=$RC safe_kept=$([ -e "$SCRATCH/ok2/f" ] && echo yes || echo no) unsafe_kept=$([ -e "$OUT/keep/f" ] && echo yes || echo no)"

ln -s "$OUT" "$SCRATCH/sl"
mkdir -p "$OUT/victim"
touch "$OUT/victim/f"
child real 'rm -rf "$SCRATCH/sl/victim"'
assert_eq "9.3 a symlinked parent that leads outside is refused" "rc=1 victim_kept=yes" \
	"rc=$RC victim_kept=$([ -e "$OUT/victim/f" ] && echo yes || echo no)"

child real 'rm -rf "$SCRATCH/sl/"'
assert_eq "9.4 a trailing slash on a symlink to outside is refused" "rc=1 target_kept=yes" \
	"rc=$RC target_kept=$([ -e "$OUT/victim/f" ] && echo yes || echo no)"

child real 'rm -rf "$SCRATCH/sl"'
assert_eq "9.5 the symlink itself is removed and its target stays" "rc=0 link_gone=yes target_kept=yes" \
	"rc=$RC link_gone=$([ -L "$SCRATCH/sl" ] && echo no || echo yes) target_kept=$([ -e "$OUT/victim/f" ] && echo yes || echo no)"

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$SAFE_RM"
fi

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo
[ "$FAIL" -eq 0 ]
