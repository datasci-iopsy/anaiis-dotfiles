#!/usr/bin/env bash
# tests/test-install-bashrc.sh -- verify install.sh's ~/.bashrc wiring and
# its CI mode, by running the real installer against a throwaway HOME.
#
# Tests:
#   - install.sh --bashrc-only adds the PATH line when absent
#   - install.sh --bashrc-only normalises a bare duplicate (two export PATH lines)
#   - install.sh --bashrc-only handles an if-guard form without leaving a
#     stray fi or duplicates (the exact failure mode that caused the bug)
#   - install.sh --bashrc-only is idempotent: two runs leave exactly one PATH line
#   - the resulting .bashrc always passes bash -n (syntax check)
#   - install.sh --symlinks-only creates the ~/.claude links and stops before
#     the shell-config phase (used by CI)
#
# Earlier versions of this file re-implemented the installer's awk block
# inside the test and asserted on that copy, so a regression in install.sh
# could not fail them (tasks/trim-candidates.md, 2026-09-07). The
# --bashrc-only mode exists so the installer itself is what runs here.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${INSTALL_SH:-$REPO_DIR/install.sh}" # INSTALL_SH points the suite at a scratch copy (fail-to-fail check)

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_eq() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' \
			"$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

assert_syntax_ok() {
	local name="$1" file="$2"
	if bash -n "$file" 2>/dev/null; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s (bash -n failed)\n' "$name"
		bash -n "$file" 2>&1 | sed 's/^/        /'
		FAIL=$((FAIL + 1))
	fi
}

# Run the installer's shell-config phase with HOME pointed at the directory
# that holds the mock .bashrc. The installer reads and rewrites $HOME/.bashrc.
run_bashrc_phase() {
	local mock="$1"
	HOME="$(dirname "$mock")" bash "$INSTALL" --bashrc-only >/dev/null 2>&1
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

if [ -n "${COV:-}" ]; then
	# shellcheck source-path=SCRIPTDIR
	# shellcheck source=lib/cov.sh
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$TMPDIR_TEST/cov.log"
fi

# ---------------------------------------------------------------------------
# Test 1: PATH line absent -- should be added
# Fails if install.sh stops appending the canonical export line.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/absent"
MOCK="$TMPDIR_TEST/absent/.bashrc"
printf '# minimal bashrc\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "adds PATH when absent" "1" "$count"
assert_syntax_ok "syntax ok after adding PATH" "$MOCK"

# ---------------------------------------------------------------------------
# Test 2: Bare duplicate (two identical export PATH lines)
# Fails if install.sh's awk block stops stripping prior PATH lines before
# appending.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/duplicate"
MOCK="$TMPDIR_TEST/duplicate/.bashrc"
# shellcheck disable=SC2016 # $HOME stays literal in the mock file
printf '# minimal bashrc\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "deduplicates bare duplicate" "1" "$count"
assert_syntax_ok "syntax ok after dedup" "$MOCK"

# ---------------------------------------------------------------------------
# Test 3: if-guard form (the exact failure mode that caused the bug)
# Fails if install.sh's awk block drops the in_guard handling: the guarded
# export would survive (two PATH lines) or the closing fi would be orphaned.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/ifguard"
MOCK="$TMPDIR_TEST/ifguard/.bashrc"
cat >"$MOCK" <<'EOF'
# minimal bashrc
if [[ ":$PATH:" != *":$HOME/anaiis-dotfiles/bin:"* ]]; then
	export PATH="$HOME/anaiis-dotfiles/bin:$PATH"
fi
[ -f ~/.bashrc.local ] && source ~/.bashrc.local
EOF
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "if-guard: exactly one PATH line after normalise" "1" "$count"
stray_fi=$(grep -c '^fi$' "$MOCK" || true)
assert_eq "if-guard: no stray fi remaining" "0" "$stray_fi"
assert_syntax_ok "syntax ok after if-guard normalise" "$MOCK"

# ---------------------------------------------------------------------------
# Test 4: Idempotency -- running twice gives same result as once
# Fails if install.sh appends without first stripping the line it added on
# the previous run.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/idempotent"
MOCK="$TMPDIR_TEST/idempotent/.bashrc"
printf '# minimal bashrc\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_bashrc_phase "$MOCK"
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "idempotent: two runs produce exactly one PATH line" "1" "$count"
assert_syntax_ok "syntax ok after two runs" "$MOCK"

# ---------------------------------------------------------------------------
# Test 5: --symlinks-only links ~/.claude and stops before shell config
#
# Fail-to-fail: the .bashrc assertion fails if the flag is ignored or if the
# early exit is placed after the ~/.bashrc block (a PATH line would appear);
# the memory-folder assertion fails if the exit is placed before the Directories
# section; the .lintr assertion fails if the exit is placed after R Style.
# ---------------------------------------------------------------------------
FAKE_HOME="$TMPDIR_TEST/home_symlinks_only"
mkdir -p "$FAKE_HOME"
printf '# untouched\n' >"$FAKE_HOME/.bashrc"
HOME="$FAKE_HOME" bash "$INSTALL" --symlinks-only >/dev/null 2>&1
rc=$?
assert_eq "--symlinks-only: exits 0" "0" "$rc"
assert_eq "--symlinks-only: .bashrc untouched" "# untouched" "$(cat "$FAKE_HOME/.bashrc")"
# install.sh makes ~/.claude/memory a real folder with an index, not a link.
mem_state=$([ -d "$FAKE_HOME/.claude/memory" ] && [ ! -L "$FAKE_HOME/.claude/memory" ] \
	&& [ -f "$FAKE_HOME/.claude/memory/MEMORY.md" ] && echo folder || echo other)
assert_eq "--symlinks-only: ~/.claude/memory is a real folder with MEMORY.md" "folder" "$mem_state"
lintr_present=$([ -e "$FAKE_HOME/.lintr" ] && echo 1 || echo 0)
assert_eq "--symlinks-only: .lintr not linked" "0" "$lintr_present"

# ---------------------------------------------------------------------------
# Tests 6 to 12: a fresh machine has no .bashrc and no .bash_profile.
#
# Why: on a fresh Mac the installer aborted at its first read of ~/.bashrc, and a
# new ~/.bashrc is dead code unless a login shell sources it (Terminal.app starts
# login shells, and bash reads ~/.bash_profile first).
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # $HOME stays literal: this is the text that the installer writes
PROFILE_LINE='[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'

# Checksum of file $1, or a marker when it is absent: two absent files must not compare equal.
sum_of() {
	if [ -f "$1" ]; then cksum <"$1"; else echo "<missing $1>"; fi
}

# Run the shell-config phase against HOME $1 and keep its output in $OUT.
run_capture() {
	OUT="$(HOME="$1" bash "$INSTALL" --bashrc-only 2>&1)"
	RC=$?
}

# ---- Test 6: no .bashrc at all -------------------------------------------
# Fails if the installer stops creating the file (the read of a missing file aborts).
NOBASHRC="$TMPDIR_TEST/nobashrc"
mkdir -p "$NOBASHRC"
run_capture "$NOBASHRC"
FIRST_OUT="$OUT"
assert_eq "no .bashrc: exits 0" "0" "$RC"
assert_eq "no .bashrc: file is created" "yes" "$([ -f "$NOBASHRC/.bashrc" ] && echo yes || echo no)"
assert_eq "no .bashrc: one PATH line" "1" "$(grep -c 'anaiis-dotfiles/bin' "$NOBASHRC/.bashrc" || true)"
assert_eq "no .bashrc: one shared.bash source line" "1" \
	"$(grep -c 'anaiis-dotfiles/bash/shared.bash' "$NOBASHRC/.bashrc" || true)"
assert_syntax_ok "no .bashrc: syntax ok" "$NOBASHRC/.bashrc"

# ---- Test 7: second run leaves the file byte-identical -------------------
# Fails if a re-run strips the PATH line and appends it again (the PATH line moves
# below the source line and one blank line is added per run).
FIRST_SUM="$(sum_of "$NOBASHRC/.bashrc")"
run_capture "$NOBASHRC"
assert_eq "second run: exits 0" "0" "$RC"
assert_eq "second run: .bashrc is byte-identical" "$FIRST_SUM" "$(sum_of "$NOBASHRC/.bashrc")"
run_capture "$NOBASHRC"
assert_eq "third run: .bashrc is byte-identical" "$FIRST_SUM" "$(sum_of "$NOBASHRC/.bashrc")"

# ---- Test 8: no .bash_profile: the installer creates one -----------------
assert_eq "no .bash_profile: file is created" "yes" "$([ -f "$NOBASHRC/.bash_profile" ] && echo yes || echo no)"
assert_eq "no .bash_profile: exactly one line" "1" "$(grep -c . "$NOBASHRC/.bash_profile" || true)"
assert_eq "no .bash_profile: the line is the guarded source line" "$PROFILE_LINE" "$(cat "$NOBASHRC/.bash_profile")"
assert_eq "no .bash_profile: first run reports the new file" "1" \
	"$(printf '%s\n' "$FIRST_OUT" | grep -c '^  add  .*\.bash_profile' || true)"
PROF_SUM="$(sum_of "$NOBASHRC/.bash_profile")"
run_capture "$NOBASHRC"
assert_eq "no .bash_profile: second run leaves it identical" "$PROF_SUM" "$(sum_of "$NOBASHRC/.bash_profile")"
assert_eq "no .bash_profile: second run prints no add line" "0" \
	"$(printf '%s\n' "$OUT" | grep -c '^  add ' || true)"
# The created line must work: it sources .bashrc when present and stays quiet when absent.
RUNHOME="$TMPDIR_TEST/runprofile"
mkdir -p "$RUNHOME"
cp "$NOBASHRC/.bash_profile" "$RUNHOME/.bash_profile"
assert_eq "profile line: no .bashrc, no output" "" "$(HOME="$RUNHOME" bash -c '. "$HOME/.bash_profile"' 2>&1)"
printf 'echo bashrc-ran\n' >"$RUNHOME/.bashrc"
assert_eq "profile line: .bashrc present, it runs" "bashrc-ran" "$(HOME="$RUNHOME" bash -c '. "$HOME/.bash_profile"' 2>&1)"

# ---- Test 9: .bash_profile already sources .bashrc -----------------------
PROF_OK="$TMPDIR_TEST/profile_ok"
mkdir -p "$PROF_OK"
printf '# mine\n[ -r ~/.bashrc ] && source ~/.bashrc\n' >"$PROF_OK/.bash_profile"
OK_SUM="$(sum_of "$PROF_OK/.bash_profile")"
run_capture "$PROF_OK"
assert_eq "profile with .bashrc line: exits 0" "0" "$RC"
assert_eq "profile with .bashrc line: file untouched" "$OK_SUM" "$(sum_of "$PROF_OK/.bash_profile")"
assert_eq "profile with .bashrc line: no note" "0" "$(printf '%s\n' "$OUT" | grep -c '^  note ' || true)"

# ---- Test 10: .bash_profile exists and never mentions .bashrc ------------
PROF_NO="$TMPDIR_TEST/profile_no"
mkdir -p "$PROF_NO"
printf '# mine\nexport EDITOR=vi\n' >"$PROF_NO/.bash_profile"
NO_SUM="$(sum_of "$PROF_NO/.bash_profile")"
run_capture "$PROF_NO"
assert_eq "profile without .bashrc line: exits 0" "0" "$RC"
assert_eq "profile without .bashrc line: file untouched" "$NO_SUM" "$(sum_of "$PROF_NO/.bash_profile")"
assert_eq "profile without .bashrc line: one note line" "1" "$(printf '%s\n' "$OUT" | grep -c '^  note ' || true)"
assert_eq "profile without .bashrc line: the note shows the fix line" "1" \
	"$(printf '%s\n' "$OUT" | grep '^  note ' | grep -cF "$PROFILE_LINE" || true)"

# ---- Test 11: no .bash_profile, but a .profile that bash would stop reading
# Why: bash reads the first of .bash_profile, .bash_login, .profile. A new
# .bash_profile would hide the other two, so the installer leaves them in charge.
PROF_HID="$TMPDIR_TEST/profile_hidden"
mkdir -p "$PROF_HID"
printf 'export FROM_PROFILE=1\n' >"$PROF_HID/.profile"
run_capture "$PROF_HID"
assert_eq "only .profile exists: exits 0" "0" "$RC"
assert_eq "only .profile exists: no .bash_profile is created" "no" "$([ -e "$PROF_HID/.bash_profile" ] && echo yes || echo no)"
assert_eq "only .profile exists: one note line" "1" "$(printf '%s\n' "$OUT" | grep -c '^  note ' || true)"

# ---- Test 12: install.sh holds no em dash --------------------------------
# The byte sequence is built with printf so that this file holds no em dash itself.
EMDASH="$(printf '\342\200\224')"
assert_eq "install.sh has no em dash" "0" "$(LC_ALL=C grep -c "$EMDASH" "$INSTALL" || true)"

# ---- Test 13: a commented-out shared.bash line is not a source line ------
# Why: the shell never reads a comment. If the installer counts it, --bashrc-only (the fix that
# bootstrap-doctor.sh prints) changes nothing and the shell still loads no shared.bash.
CMT_SRC="$TMPDIR_TEST/commented_source"
mkdir -p "$CMT_SRC"
# shellcheck disable=SC2016 # $HOME stays literal in the mock file
printf '# mine\n# source "$HOME/anaiis-dotfiles/bash/shared.bash"\n' >"$CMT_SRC/.bashrc"
run_capture "$CMT_SRC"
assert_eq "commented source line: exits 0" "0" "$RC"
# shellcheck disable=SC2016 # \$ is a regular-expression escape for a literal dollar sign
assert_eq "commented source line: an active source line is added" "1" \
	"$(grep -cx 'source "\$HOME/anaiis-dotfiles/bash/shared\.bash"' "$CMT_SRC/.bashrc" || true)"
# An active line that ends in a comment is still a source line: the installer adds nothing.
ACT_SRC="$TMPDIR_TEST/trailing_comment_source"
mkdir -p "$ACT_SRC"
# shellcheck disable=SC2016 # $HOME stays literal in the mock file
printf '# mine\nsource "$HOME/anaiis-dotfiles/bash/shared.bash" # prompt\n' >"$ACT_SRC/.bashrc"
run_capture "$ACT_SRC"
assert_eq "source line with a trailing comment: nothing is added" "0" \
	"$(printf '%s\n' "$OUT" | grep -c '^  add  source shared.bash' || true)"

# ---- Test 14: a commented-out .bashrc line in .bash_profile is not a source line
CMT_PROF="$TMPDIR_TEST/profile_commented"
mkdir -p "$CMT_PROF"
printf '# . ~/.bashrc\n' >"$CMT_PROF/.bash_profile"
run_capture "$CMT_PROF"
assert_eq "profile with a commented .bashrc line: one note line" "1" "$(printf '%s\n' "$OUT" | grep -c '^  note ' || true)"

# ---- Test 15: a file whose name only starts with .bashrc is not .bashrc ---
# Why: a login shell that reads a file which sources only ~/.bashrc.local never loads ~/.bashrc or
# shared.bash. A substring test counted that file as healthy, so the installer stayed silent.
n=0
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
for line in 'source "$HOME/.bashrc.local"' '. ~/.bashrc_old' '[ -f ~/.bashrc.bak ] && . ~/.bashrc.bak'; do
	n=$((n + 1))
	OTHER_NAME="$TMPDIR_TEST/profile_other_name_$n"
	mkdir -p "$OTHER_NAME"
	printf '%s\n' "$line" >"$OTHER_NAME/.bash_profile"
	run_capture "$OTHER_NAME"
	assert_eq "profile with only '$line': one note line" "1" "$(printf '%s\n' "$OUT" | grep -c '^  note ' || true)"
	assert_eq "profile with only '$line': no ok line" "0" "$(printf '%s\n' "$OUT" | grep -c 'mentions .bashrc' || true)"
done

# ---- Test 16: each real way to source .bashrc still counts ---------------
# Why: the boundary after .bashrc must not reject a source line that is written another way, or
# that ends in a comment.
n=0
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
for line in \
	'[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' \
	'source ~/.bashrc' \
	'. ~/.bashrc' \
	'. "${HOME}/.bashrc"' \
	'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi' \
	'[ -r ~/.bashrc ] && source ~/.bashrc # shell config'; do
	n=$((n + 1))
	REAL_FORM="$TMPDIR_TEST/profile_real_form_$n"
	mkdir -p "$REAL_FORM"
	printf '%s\n' "$line" >"$REAL_FORM/.bash_profile"
	run_capture "$REAL_FORM"
	assert_eq "profile with '$line': no note" "0" "$(printf '%s\n' "$OUT" | grep -c '^  note ' || true)"
	assert_eq "profile with '$line': one ok line" "1" "$(printf '%s\n' "$OUT" | grep -c 'mentions .bashrc' || true)"
done
# A .bashrc.local line does not hide a real source line on another line of the same file.
BOTH_LINES="$TMPDIR_TEST/profile_both_lines"
mkdir -p "$BOTH_LINES"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf 'source "$HOME/.bashrc.local"\n. ~/.bashrc\n' >"$BOTH_LINES/.bash_profile"
run_capture "$BOTH_LINES"
assert_eq "profile with .bashrc.local and .bashrc lines: no note" "0" "$(printf '%s\n' "$OUT" | grep -c '^  note ' || true)"

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$INSTALL"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
