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
MKLOG="$TREE/mkdir.log"
mkdir -p "$SCRATCH" "$CWD/tests/fixtures" "$CWD/tmp/worktrees/wt" "$CWD/node_modules" "$CWD/src" \
	"$CWD/.git" "$OUT" "$TMPR" "$HOMEF" "$STUB"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$RMLOG" >"$STUB/rm"
chmod +x "$STUB/rm"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$MKLOG" >"$STUB/mkdir"
chmod +x "$STUB/mkdir"

# child <mode> <snippet>: run the snippet in a clean child shell, in the fake project folder.
#   mode "stub": PATH has the logging stub first. mode "real": PATH has the real rm only.
#   mode "nocwd": like stub, but __SAFE_RM_CWD is unset. mode "noscratch": like stub, scratch unset.
#   mode "cwdscratch": like stub, but the working directory is $SCRATCH/a/b (inside the scratchpad).
#   mode "homeintmp": like stub, but HOME is a tmp.* folder under TMPDIR (a home inside a root).
#   mode "cwdhome": like stub, but the working directory is HOME. "cwdabovehome": the cwd is a parent of
#   HOME. "cwdroot": the cwd is the root folder.
#   mode "aliases": like stub, but the shell has expand_aliases on and the aliases of the owner's profile
#   (mkdir='mkdir -pv', pwd='pwd -P', ls='ls -GFhp', rm='rm -i') are defined BEFORE the file is sourced.
# Sets RC, ERR (stderr text), CALLED (yes when the stub or real rm was reached), and MKCALLED (the same for mkdir).
child() {
	local mode="$1" snippet="$2" path_dir="$STUB:/usr/bin:/bin" run_dir="$CWD" home_dir="$HOMEF"
	local pre='. "$SAFE_RM"; '
	[ "$mode" = aliases ] && pre="shopt -s expand_aliases
alias mkdir='mkdir -pv'
alias pwd='pwd -P'
alias ls='ls -GFhp'
alias rm='rm -i'
. \"\$SAFE_RM\"
"
	[ "$mode" = real ] && path_dir="/usr/bin:/bin"
	: >"$RMLOG"
	: >"$MKLOG"
	local scratch_arg="__SAFE_RM_SCRATCH=$SCRATCH" cwd_arg="__SAFE_RM_CWD=$CWD"
	[ "$mode" = noscratch ] && scratch_arg="UNUSED_A=1"
	[ "$mode" = nocwd ] && cwd_arg="UNUSED_B=1"
	if [ "$mode" = cwdscratch ]; then
		mkdir -p "$SCRATCH/a/b"
		run_dir="$SCRATCH/a/b"
		cwd_arg="__SAFE_RM_CWD=$run_dir"
	fi
	case "$mode" in
		homeintmp)
			home_dir="$TMPR/tmp.homeX"
			mkdir -p "$home_dir"
			;;
		cwdhome) run_dir="$HOMEF" ;;
		cwdabovehome) run_dir="$TREE" ;;
		cwdroot) run_dir="/" ;;
	esac
	case "$mode" in
		cwdhome | cwdabovehome | cwdroot) cwd_arg="__SAFE_RM_CWD=$run_dir" ;;
	esac
	# BASH_ENV, BASH_XTRACEFD, and PS4 pass through env -i so that COV=1 can trace the child shell.
	ERR="$(cd "$run_dir" && env -i PATH="$path_dir" HOME="$home_dir" TMPDIR="$TMPR" "$scratch_arg" "$cwd_arg" \
		BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
		SCRATCH="$SCRATCH" CWD="$CWD" OUT="$OUT" TMPR="$TMPR" HOMEF="$HOMEF" ALIAS="$TREE/alias" TREE="$TREE" SAFE_RM="$SAFE_RM" \
		"$BASH" -c "$pre$snippet" 2>&1 >/dev/null)"
	RC=$?
	CALLED=no
	[ -s "$RMLOG" ] && CALLED=yes
	MKCALLED=no
	[ -s "$MKLOG" ] && MKCALLED=yes
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

# expect_stop <name> <snippet> [mode]: the guard refuses and the WHOLE command stops. The snippet marks
# every statement that runs after the refusal by writing the word AFTER to stderr (F9).
expect_stop() {
	child "${3:-stub}" "$2"
	local after=no refused=no
	printf '%s' "$ERR" | grep -qF -- "AFTER" && after=yes
	printf '%s' "$ERR" | grep -qF -- "refused" && refused=yes
	assert_eq "$1" "rc=1 called=no refused=yes after=no" "rc=$RC called=$CALLED refused=$refused after=$after"
}

# expect_log <name> <snippet> <expected-log-line> [mode]: the guard lets rm run and the real (or stub) rm
# receives exactly this argument line.
expect_log() {
	child "${4:-stub}" "$2"
	assert_eq "$1" "rc=0 log=$3" "rc=$RC log=$(cat "$RMLOG")"
}

# expect_mk_log <name> <snippet> <expected-log-line> [mode]: the guard lets mkdir run and the stub (or
# real) mkdir receives exactly this argument line.
expect_mk_log() {
	child "${4:-stub}" "$2"
	assert_eq "$1" "rc=0 log=$3" "rc=$RC log=$(cat "$MKLOG")"
}

# expect_mk_refuse <name> <snippet> <needle> [mode]: the guard stops mkdir (RC 1, mkdir not reached, reason shown).
expect_mk_refuse() {
	child "${4:-stub}" "$2"
	local seen=no
	printf '%s' "$ERR" | grep -qF -- "$3" && seen=yes
	assert_eq "$1" "rc=1 mkdir_called=no reason=yes" "rc=$RC mkdir_called=$MKCALLED reason=$seen"
}

echo "--- 0. loading"
child stub '[ "$(type -t rm)" = function ]'
assert_eq "0.1 sourcing the file defines rm as a function" "rc=0" "rc=$RC"
child stub 'rm -rf "$OUT/f"'
assert_eq "0.2 the function, not the stub, handles the first call" "rc=1 called=no" "rc=$RC called=$CALLED"

child stub '[ "$(type -t mkdir)" = function ]'
assert_eq "0.3 sourcing the file defines mkdir as a function" "rc=0" "rc=$RC"

echo "--- 1. allowed: the scratchpad"
expect_pass "1.1 file inside the scratchpad" 'rm -rf "$SCRATCH/a"'
expect_pass "1.2 deep path inside the scratchpad" 'rm -rf "$SCRATCH/a/b/c/d"'
ln -s "$TREE" "$TREE/alias"
expect_pass "1.3 scratchpad reached through a symlinked spelling" 'rm -rf "$ALIAS/session/scratchpad/z"'
expect_pass "1.4 a path that does not exist yet (the delete is a no-op)" 'rm -rf "$SCRATCH/not-there"'
expect_pass "1.5 several operands, all inside" 'rm -rf "$SCRATCH/a" "$SCRATCH/b" "$SCRATCH/c"'
mkdir -p "$SCRATCH/dir"
expect_pass "1.6 a trailing slash on an ordinary folder" 'rm -rf "$SCRATCH/dir/"'

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
expect_log "4.8 flags and no operand: passed on unchanged so rm prints its own usage error" 'rm -rf' "-rf"

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
expect_refuse "5.21 an empty operand names the reason" 'rm -rf ""' "the operand is empty"
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

echo "--- 10. the guard reads only copies that it made at source time (F1, F10 part 1, F13)"
# Each write below targets a name the guard must not read at call time. The write and the rm sit on
# separate lines: a refused write to a read-only name abandons the rest of its own line.
expect_refuse "10.1 a write to the scratchpad variable has no effect" \
	'__SAFE_RM_SCRATCH="$OUT"
rm -rf "$OUT/f"' "refused"
expect_refuse "10.2 a for loop over the scratchpad variable has no effect" \
	'for __SAFE_RM_SCRATCH in "$OUT"; do :; done
rm -rf "$OUT/f"' "refused"
expect_refuse "10.3 printf -v on the working-directory variable has no effect" \
	'printf -v __SAFE_RM_CWD "%s" "$OUT"
rm -rf "$OUT/node_modules"' "refused"
expect_refuse "10.4 a changed HOME does not move the home guard" \
	'HOME=/nonexistent
rm -rf "$TMPR/tmp.homeX"' "home folder" homeintmp
expect_refuse "10.5 a changed TMPDIR does not move the tmp.* root" \
	'TMPDIR="$OUT"
rm -rf "$OUT/tmp.x"' "refused"
expect_pass "10.6 a changed PATH does not change which rm runs" \
	'PATH=/nonexistent
rm -rf "$SCRATCH/a"'
expect_pass "10.7 a changed PWD does not move relative operands" \
	'PWD="$OUT"
rm -rf node_modules'
expect_refuse "10.8 a relative operand resolves against the real directory after cd (outside)" \
	'cd "$OUT" && rm -rf node_modules' "refused"
expect_pass "10.9 a relative operand resolves against the real directory after cd (inside)" \
	'cd "$SCRATCH" && rm -rf thing'

# Every copy the function reads must refuse a write. A name that stays writable lets a later statement
# move a root. The subshell isolates the write; a refused write fails, so only a writable name prints.
child stub 'for v in __SAFE_RM_CWD __SAFE_RM_SCRATCH __SAFE_RM_REAL __SAFE_RM_REALMKDIR __SAFE_RM_CWDP __SAFE_RM_SCRATCHP __SAFE_RM_HOMEP __SAFE_RM_TMPP __SAFE_RM_CWDROOTS; do
(eval "$v=x") 2>/dev/null && echo "WRITABLE $v" >&2
done
true'
assert_eq "10.9b every captured variable refuses a write" "rc=0 writable=" "rc=$RC writable=$(printf '%s' "$ERR" | grep -o 'WRITABLE [A-Z_]*' | tr '\n' ' ')"

NOPATH_OUT="$(env -i PATH=/nonexistent HOME="$HOMEF" TMPDIR="$TMPR" __SAFE_RM_CWD="$CWD" SAFE_RM="$SAFE_RM" BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
	"$BASH" -c '. "$SAFE_RM"; echo "src=$? fn=$(type -t rm)"' 2>/dev/null)"
assert_eq "10.10 sourcing fails and defines no rm when no rm program exists on PATH" "src=1 fn=" "$NOPATH_OUT"
ONLYMK_DIR="$TREE/onlymkdir"
mkdir -p "$ONLYMK_DIR"
cp /bin/mkdir "$ONLYMK_DIR/mkdir"
ONLYMK_OUT="$(env -i PATH="$ONLYMK_DIR" HOME="$HOMEF" TMPDIR="$TMPR" __SAFE_RM_CWD="$CWD" SAFE_RM="$SAFE_RM" BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
	"$BASH" -c '. "$SAFE_RM"; echo "src=$? rm=$(type -t rm) mkdir=$(type -t mkdir)"' 2>/dev/null)"
assert_eq "10.10b sourcing fails and defines no function when only mkdir exists on PATH" "src=1 rm= mkdir=file" "$ONLYMK_OUT"

echo "--- 11. the checked list is the deleted list (F8)"
PSCRATCH="$(cd "$SCRATCH" && pwd -P)"
expect_log "11.1 every flag and operand reach rm, after --, as resolved paths" \
	'rm -rf -v "$SCRATCH/a" "$SCRATCH/b" "$SCRATCH/c"' "-rf -v -- $PSCRATCH/a $PSCRATCH/b $PSCRATCH/c"
expect_log "11.2 a symlinked spelling is replaced by the physical path" \
	'rm -rf "$ALIAS/session/scratchpad/z"' "-rf -- $PSCRATCH/z"
expect_refuse "11.3 a word after the first operand is an operand, not a flag (BSD rm)" \
	'rm "$SCRATCH/a" -rf' "refused"
touch "$CWD/-rf" "$SCRATCH/keep-me"
child real 'rm "$SCRATCH/keep-me" -rf'
assert_eq "11.4 the file that is named like a flag survives, and so does the other operand" \
	"rc=1 flagfile_kept=yes other_kept=yes" \
	"rc=$RC flagfile_kept=$([ -e "$CWD/-rf" ] && echo yes || echo no) other_kept=$([ -e "$SCRATCH/keep-me" ] && echo yes || echo no)"
rm -f "$CWD/-rf" "$SCRATCH/keep-me"

echo "--- 12. a refusal stops the whole command (F9)"
expect_stop "12.1 a statement after a refused rm does not run" 'rm -rf "$OUT/f"; echo AFTER >&2'
expect_stop "12.2 later loop iterations do not run" 'for m in a b; do rm -rf "$OUT/$m"; echo AFTER >&2; done'
expect_stop "12.3 a refused flag stops the command" 'rm -rx "$SCRATCH/a"; echo AFTER >&2'

echo "--- 13. working-directory roots are off when the directory is HOME or above (F10 part 1)"
expect_refuse "13.1 cwd is HOME: a disposable folder is not a root" 'rm -rf "$HOMEF/node_modules"' "refused" cwdhome
expect_pass "13.2 cwd is HOME: the scratchpad root still works" 'rm -rf "$SCRATCH/a"' cwdhome
expect_refuse "13.3 cwd is a parent of HOME: a disposable folder is not a root" 'rm -rf "$TREE/node_modules"' "refused" cwdabovehome
expect_pass "13.4 cwd is a parent of HOME: the tmp.* root still works" 'rm -rf "$TMPR/tmp.x"' cwdabovehome
expect_refuse "13.5 cwd is the root folder: every operand is refused" 'rm -rf "$SCRATCH/a"' "no working directory" cwdroot

echo "--- 14. HOME inside a root"
expect_refuse "14.1 HOME below TMPDIR is still never deleted" 'rm -rf "$HOME"' "home folder" homeintmp

echo "--- 15. mkdir is guarded with the same roots as rm (T-E4d)"
expect_mk_log "15.1 inside the scratchpad: flags, --, and the resolved path reach mkdir" \
	'mkdir -p "$SCRATCH/mk/a"' "-p -- $PSCRATCH/mk/a"
expect_mk_log "15.2 a disposable folder in the working directory" 'mkdir -p "$CWD/node_modules/x"' "-p -- $(cd "$CWD" && pwd -P)/node_modules/x"
expect_mk_log "15.3 below tests/fixtures" 'mkdir "$CWD/tests/fixtures/sub"' "-- $(cd "$CWD" && pwd -P)/tests/fixtures/sub"
expect_mk_log "15.4 below tmp" 'mkdir -p "$CWD/tmp/x"' "-p -- $(cd "$CWD" && pwd -P)/tmp/x"
expect_mk_log "15.5 a tmp.* folder under TMPDIR" 'mkdir -p "$TMPR/tmp.abc/x"' "-p -- $(cd "$TMPR" && pwd -P)/tmp.abc/x"
expect_mk_log "15.6 nested -p below folders that do not exist yet" 'mkdir -p "$SCRATCH/n1/n2/n3/n4"' "-p -- $PSCRATCH/n1/n2/n3/n4"
expect_mk_log "15.7 several operands, all inside" 'mkdir -p "$SCRATCH/s1" "$SCRATCH/s2"' "-p -- $PSCRATCH/s1 $PSCRATCH/s2"
expect_mk_log "15.8 -pv in one word, and -- before an operand that looks like a flag" 'mkdir -pv -- "$SCRATCH/-weird"' "-pv -- $PSCRATCH/-weird"
expect_mk_log "15.9 a symlinked spelling is replaced by the physical path" 'mkdir -p "$ALIAS/session/scratchpad/z"' "-p -- $PSCRATCH/z"
expect_mk_log "15.10 a relative operand starts at the real directory after cd" 'cd "$SCRATCH" && mkdir -p thing' "-p -- $PSCRATCH/thing"
expect_mk_refuse "15.11 a relative operand after cd to a folder outside every root" 'cd "$OUT" && mkdir -p thing' "refused"
expect_mk_refuse "15.12 outside every root" 'mkdir -p "$OUT/new"' "refused"
expect_mk_refuse "15.13 a symlinked parent that leads outside" 'ln -s "$OUT" "$SCRATCH/mkl" && mkdir -p "$SCRATCH/mkl/new"' "refused"
expect_mk_refuse "15.14 a .. component" 'mkdir -p "$SCRATCH/../x"' "refused"
expect_mk_refuse "15.15 a .git folder" 'mkdir -p "$CWD/node_modules/.git/x"' "refused"
expect_mk_refuse "15.16 the root folder" 'mkdir -p /' "refused"
expect_mk_refuse "15.17 the home folder" 'mkdir -p "$HOMEF"' "home folder"
expect_mk_refuse "15.18 the working directory itself" 'mkdir -p "$CWD"' "refused"
expect_mk_refuse "15.19 a parent of the working directory" 'mkdir -p "$TREE"' "refused"
expect_mk_refuse "15.20 the scratchpad itself" 'mkdir -p "$SCRATCH"' "refused"
expect_mk_refuse "15.21 an empty operand names the reason" 'mkdir -p ""' "the operand is empty"
expect_mk_refuse "15.22 -m is not an allowed flag" 'mkdir -m 755 "$SCRATCH/a"' "flag"
expect_mk_refuse "15.23 a long flag is not allowed" 'mkdir --parents "$SCRATCH/a"' "flag"
expect_mk_refuse "15.24 a flag word after the first operand is an operand" 'mkdir "$SCRATCH/a" -p' "refused"
expect_mk_refuse "15.25 one refused operand among two" 'mkdir "$SCRATCH/a" "$OUT/b"' "refused"
expect_stop "15.26 a refused mkdir stops the whole command" 'mkdir -p "$OUT/new"; echo AFTER >&2'
expect_mk_log "15.27 a changed PATH does not change which mkdir runs" 'PATH=/nonexistent
mkdir -p "$SCRATCH/pp"' "-p -- $PSCRATCH/pp"
expect_mk_log "15.28 flags and no operand: passed on unchanged so mkdir prints its own usage error" 'mkdir -p' "-p"

# Real mkdir in the throwaway tree. A victim path outside every root must not appear.
child real 'mkdir -p "$SCRATCH/real-mk/a/b"'
assert_eq "15.30 a safe nested operand is really created" "rc=0 made=yes" "rc=$RC made=$([ -d "$SCRATCH/real-mk/a/b" ] && echo yes || echo no)"
child real 'mkdir "$SCRATCH/mk-ok" "$OUT/mk-bad"'
assert_eq "15.31 a mixed call creates nothing, not even the safe operand" "rc=1 safe_made=no unsafe_made=no" \
	"rc=$RC safe_made=$([ -e "$SCRATCH/mk-ok" ] && echo yes || echo no) unsafe_made=$([ -e "$OUT/mk-bad" ] && echo yes || echo no)"
child real 'mkdir -p "$OUT/mk-victim/deep"'
assert_eq "15.32 an operand outside every root is not created" "rc=1 victim_made=no" "rc=$RC victim_made=$([ -e "$OUT/mk-victim" ] && echo yes || echo no)"

NOMKDIR_DIR="$TREE/onlyrm"
mkdir -p "$NOMKDIR_DIR"
cp "$STUB/rm" "$NOMKDIR_DIR/rm"
NOMKDIR_OUT="$(env -i PATH="$NOMKDIR_DIR" HOME="$HOMEF" TMPDIR="$TMPR" __SAFE_RM_CWD="$CWD" SAFE_RM="$SAFE_RM" BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
	"$BASH" -c '. "$SAFE_RM"; echo "src=$? rm=$(type -t rm) mkdir=$(type -t mkdir)"' 2>/dev/null)"
assert_eq "15.33 sourcing fails and defines no function (rm stays the plain program) when no mkdir program exists on PATH" "src=1 rm=file mkdir=" "$NOMKDIR_OUT"

echo "--- 16. aliases of the harness shell and clustered flags (T-E4e)"
# The harness shell loads the owner's aliases and has expand_aliases on. An alias word such as mkdir is
# expanded while the file is parsed, so "mkdir() {" is a syntax error unless alias expansion is off during
# the parse. The tests above run under bash -c with no aliases, which hid the defect.
child aliases 'echo "fn=$(declare -F rm mkdir | tr "\n" ,) alias_mkdir=$(alias mkdir) ea=$(shopt -p expand_aliases) left=${__sr_ea+set}" >&2'
assert_eq "16.1 with aliases defined: both functions exist, the alias is still defined, expansion is on, no helper variable is left" \
	"fn=rm,mkdir, alias_mkdir=alias mkdir='mkdir -pv' ea=shopt -s expand_aliases left=" "$ERR"
expect_mk_log "16.2 the alias still reaches the owner's command: -pv from the alias is an allowed cluster" \
	'cd "$SCRATCH" && mkdir ali' "-pv -- $PSCRATCH/ali" aliases
expect_mk_refuse "16.3 with the alias on, an operand outside every root is refused" 'mkdir "$OUT/ali-out"' "refused" aliases
expect_refuse "16.4 an rm alias that adds -i makes the guard refuse and name the flag (fail closed)" \
	'rm -rf "$SCRATCH/a"' "'-i'" aliases
child stub 'echo "ea=$(shopt -p expand_aliases) left=${__sr_ea+set}" >&2'
assert_eq "16.5 with alias expansion off, it is off again after sourcing (the file restores the saved state)" \
	"ea=shopt -u expand_aliases left=" "$ERR"
ALIAS_FAIL_OUT="$(env -i PATH="$TREE/onlyrm" HOME="$HOMEF" TMPDIR="$TMPR" __SAFE_RM_CWD="$CWD" SAFE_RM="$SAFE_RM" BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
	"$BASH" -c 'shopt -s expand_aliases
. "$SAFE_RM"
echo "src=$? ea=$(shopt -p expand_aliases) left=${__sr_ea+set}"' 2>/dev/null)"
assert_eq "16.6 a failed load restores the state too (expansion on stays on, no helper variable is left)" \
	"src=1 ea=shopt -s expand_aliases left=" "$ALIAS_FAIL_OUT"
ALIAS_FAIL2_OUT="$(env -i PATH="$TREE/onlymkdir" HOME="$HOMEF" TMPDIR="$TMPR" __SAFE_RM_CWD="$CWD" SAFE_RM="$SAFE_RM" BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
	"$BASH" -c 'shopt -s expand_aliases
. "$SAFE_RM"
echo "src=$? ea=$(shopt -p expand_aliases) left=${__sr_ea+set}"' 2>/dev/null)"
assert_eq "16.6b the same when no rm program exists (the other failure path)" \
	"src=1 ea=shopt -s expand_aliases left=" "$ALIAS_FAIL2_OUT"
# shopt -p prints the state and returns 1 when the option is off. Under set -e that status would stop the load.
ERREXIT_OUT="$(env -i PATH="$STUB:/usr/bin:/bin" HOME="$HOMEF" TMPDIR="$TMPR" __SAFE_RM_CWD="$CWD" __SAFE_RM_SCRATCH="$SCRATCH" SAFE_RM="$SAFE_RM" \
	BASH_ENV="${BASH_ENV:-}" BASH_XTRACEFD="${BASH_XTRACEFD:-}" PS4="${PS4:-+ }" \
	"$BASH" -c 'set -e
. "$SAFE_RM"
echo "src=$? ea=$(shopt -p expand_aliases) fn=$(declare -F rm mkdir | tr "\n" ,)"' 2>/dev/null)"
assert_eq "16.13 the file loads under set -e with alias expansion off, and the off state is restored" \
	"src=0 ea=shopt -u expand_aliases fn=rm,mkdir," "$ERREXIT_OUT"
expect_log "16.7 -rfv is an allowed cluster" 'rm -rfv "$SCRATCH/a"' "-rfv -- $PSCRATCH/a"
expect_log "16.8 -fr is an allowed cluster" 'rm -fr "$SCRATCH/a"' "-fr -- $PSCRATCH/a"
expect_mk_log "16.9 -vp is an allowed cluster" 'mkdir -vp "$SCRATCH/vp"' "-vp -- $PSCRATCH/vp"
expect_refuse "16.10 rm -i names the flag" 'rm -i "$SCRATCH/a"' "'-i'"
expect_refuse "16.11 a cluster with one bad letter names the whole word" 'rm -rfi "$SCRATCH/a"' "'-rfi'"
expect_mk_refuse "16.12 mkdir -m names the flag" 'mkdir -m 755 "$SCRATCH/a"' "'-m'"

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
