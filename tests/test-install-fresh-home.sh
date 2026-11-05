#!/usr/bin/env bash
# tests/test-install-fresh-home.sh -- end to end: the real install.sh, in full mode, run twice
# against a HOME that starts empty.
#
# Why this matters: a new machine must reach a working harness with one command and no manual
# repair. The first run must not abort (SC-1). The second run must change nothing and must not
# print a link, add, created, updated, migrated, or unlink line (SC-2). Then bootstrap-doctor.sh must
# agree that the shell config and the ~/.claude links are in place, and must name every enabled
# plugin as missing, because a fresh HOME has no plugin cache.
#
# Safety: HOME is a throwaway folder. A stub gh (protocol https) is first on PATH, so no real gh
# runs and no network is used. install.sh resolves the MAIN checkout as canonical (it reads the
# first entry of `git worktree list`), so links in the test HOME point at the main checkout. In a
# linked worktree that is not the folder under test, and the test does not assume otherwise.
#
# Env override, used for the fail-to-fail check:
#   INSTALL_SH   path of the installer under test
#
# Usage: bash tests/test-install-fresh-home.sh        (COV=1 adds line coverage on bash 4.1 or later)

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${INSTALL_SH:-$REPO_DIR/install.sh}"
DOCTOR="$REPO_DIR/claude/scripts/bootstrap-doctor.sh"
WORKFLOW="$REPO_DIR/.github/workflows/tests.yml"

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

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/test-install-fresh-home.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

if [ -n "${COV:-}" ]; then
	# shellcheck source-path=SCRIPTDIR
	# shellcheck source=lib/cov.sh
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$TMPD/cov.log"
fi

# Stub gh: accepts exactly `config get git_protocol` and answers https. Any other call fails.
mkdir -p "$TMPD/stub"
cat >"$TMPD/stub/gh" <<'EOF'
#!/bin/sh
[ "$*" = "config get git_protocol" ] || {
	echo "stub gh: unexpected arguments: $*" >&2
	exit 64
}
echo https
EOF
chmod +x "$TMPD/stub/gh"

# Stub claude: accepts exactly `--version` and answers a version above the doctor minimum. Without it,
# the doctor would run the real claude, and an old install on the test machine would add a MISSING line.
cat >"$TMPD/stub/claude" <<'EOF'
#!/bin/sh
[ "$*" = "--version" ] || {
	echo "stub claude: unexpected arguments: $*" >&2
	exit 64
}
echo "2.1.318 (Claude Code)"
EOF
chmod +x "$TMPD/stub/claude"

# snapshot <home>: one checksum over the sorted paths, each regular file with its checksum, and each
# link with its target. find does not follow links, so the repo behind a link is not read.
snapshot() {
	(
		cd "$1" || exit 1
		{
			find . | LC_ALL=C sort
			find . -type f -exec cksum {} + | LC_ALL=C sort
			find . -type l -exec sh -c 'for l; do printf "%s -> %s\n" "$l" "$(readlink "$l")"; done' _ {} + | LC_ALL=C sort
		} | cksum
	)
}

# run_install: the full installer against $H. OUT holds stdout and stderr; RC the exit code.
run_install() {
	OUT="$(HOME="$H" PATH="$TMPD/stub:$PATH" "$BASH" "$INSTALL" 2>&1)"
	RC=$?
}

# Lines that report a change. Two spaces, then one of the words, then a space or the line end.
CHANGE_RE='^  (link|add|created|updated|migrated|unlink)( |$)'

H="$(mktemp -d "$TMPD/home.XXXXXX")"

echo "--- 1. the first run on an empty HOME"
assert_eq "1.1 the HOME starts empty" "" "$(ls -A "$H")"
run_install
FIRST_OUT="$OUT"
assert_eq "1.2 exit code is 0" 0 "$RC"
assert_eq "1.3 the run ends with Done." 1 "$(printf '%s\n' "$FIRST_OUT" | grep -c '^Done\.$')"
assert_eq "1.4 the first run reports changes (the check below is not vacuous)" yes \
	"$([ "$(printf '%s\n' "$FIRST_OUT" | grep -cE "$CHANGE_RE")" -gt 0 ] && echo yes || echo no)"
assert_eq "1.5 the shell config exists" yes "$([ -f "$H/.bashrc" ] && [ -f "$H/.bash_profile" ] && echo yes || echo no)"
assert_eq "1.6 one PATH line in .bashrc" 1 "$(grep -c 'anaiis-dotfiles/bin' "$H/.bashrc")"
assert_eq "1.7 one shared.bash source line in .bashrc" 1 "$(grep -c 'anaiis-dotfiles/bash/shared.bash' "$H/.bashrc")"
assert_eq "1.8 gh protocol https: the host key step skips" 1 \
	"$(printf '%s\n' "$FIRST_OUT" | grep -c '^  skip  gh git protocol is "https"')"
assert_eq "1.9 gh protocol https: no .ssh folder is created" no "$([ -e "$H/.ssh" ] && echo yes || echo no)"
assert_eq "1.10 no CLAUDE.md link is created (rules/context.md replaces it)" no \
	"$([ -L "$H/.claude/CLAUDE.md" ] || [ -e "$H/.claude/CLAUDE.md" ] && echo yes || echo no)"
assert_eq "1.11 the first run prints nothing about CLAUDE.md" 0 "$(printf '%s\n' "$FIRST_OUT" | grep -c 'CLAUDE\.md')"
assert_eq "1.12 ~/.claude/memory is a real folder, not a link" yes \
	"$([ -d "$H/.claude/memory" ] && [ ! -L "$H/.claude/memory" ] && echo yes || echo no)"
assert_eq "1.13 the new memory folder holds a MEMORY.md index" yes "$([ -f "$H/.claude/memory/MEMORY.md" ] && echo yes || echo no)"

echo "--- 2. the links point at the main checkout"
# install.sh takes the first entry of git worktree list as canonical. Outside git, the repo itself.
MAIN="$(git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null | awk '/^worktree/{sub(/^worktree /, ""); print; exit}')"
MAIN="$(cd "${MAIN:-$REPO_DIR}" && pwd -P)"
assert_eq "2.1 ~/anaiis-dotfiles links to the main checkout" "$MAIN" "$(cd "$H/anaiis-dotfiles" && pwd -P)"
assert_eq "2.2 ~/.claude/rules resolves into the main checkout" "$MAIN/claude/rules" "$(cd "$H/.claude/rules" && pwd -P)"

echo "--- 3. the second run changes nothing"
SNAP1="$(snapshot "$H")"
run_install
assert_eq "3.1 exit code is 0" 0 "$RC"
assert_eq "3.2 no line starts with link, add, created, updated, migrated, or unlink" 0 \
	"$(printf '%s\n' "$OUT" | grep -cE "$CHANGE_RE")"
assert_eq "3.3 the HOME snapshot is identical" "$SNAP1" "$(snapshot "$H")"
assert_eq "3.4 the second run ends with Done." 1 "$(printf '%s\n' "$OUT" | grep -c '^Done\.$')"

echo "--- 4. the doctor agrees"
ENABLED="$(jq '[(.enabledPlugins // {}) | to_entries[] | select(.value == true)] | length' "$H/.claude/settings.json")"
# Doctor check 7 reads the shell pin and the hook commands from the settings.json that the links reach.
# That file sits in the main checkout, which holds neither until the branch that adds them merges. Count
# the expected gap from the file itself: one line for an absent pin, one for commands with a bare bash.
# Once the main checkout holds both, GAP is 0 and this section is strict. The repo's own settings.json
# is checked by tests/test-bash-baseline.sh, which does not read through the links.
# shortcut: GAP reads the live main checkout and repeats the counting filter of the doctor. Once PR 38
# has merged, delete GAP and the two lines that set it, and assert a count of 0 for check 7.
GAP=0
[ -n "$(jq -r '.env.CLAUDE_CODE_SHELL // empty' "$H/.claude/settings.json")" ] || GAP=$((GAP + 1))
# shellcheck disable=SC2016 # ${...} stays literal: it is the text that settings.json holds
[ "$(jq '[.. | objects | select(has("command")) | .command | select(startswith("${CLAUDE_CODE_SHELL:-bash} ") | not)] | length' "$H/.claude/settings.json")" -eq 0 ] || GAP=$((GAP + 1))
OUT="$(HOME="$H" PATH="$TMPD/stub:$PATH" "$BASH" "$DOCTOR" 2>&1)"
RC=$?
okl() { printf '%s\n' "$OUT" | grep -c "$1"; }
assert_eq "4.1 ok for the PATH line" 1 "$(okl '^ok ~/.bashrc PATH line$')"
assert_eq "4.2 ok for the shared.bash line" 1 "$(okl '^ok ~/.bashrc shared.bash line$')"
assert_eq "4.3 ok for the login shell file" 1 "$(okl '^ok ~/.bash_profile mentions ~/.bashrc$')"
assert_eq "4.4 ok for all eight links" 8 "$(okl '^ok ~/.claude/[a-z.]* -> ~/anaiis-dotfiles/claude$')"
assert_eq "4.12 ok for the local memory folder" 1 "$(okl '^ok ~/.claude/memory (local folder)$')"
assert_eq "4.5 one MISSING line per enabled plugin" "$ENABLED" "$(okl '^MISSING plugin ')"
assert_eq "4.6 no other MISSING line (check 7 adds GAP lines)" "$((ENABLED + GAP))" "$(okl '^MISSING ')"
assert_eq "4.7 the host key is not needed for https" 1 "$(okl '^ok github.com host key (not needed: gh protocol is https)$')"
assert_eq "4.8 summary counts the missing plugins and the check 7 gap" "doctor: $((ENABLED + GAP)) missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
if [ "$((ENABLED + GAP))" -gt 0 ]; then WANT_RC=1; else WANT_RC=0; fi
assert_eq "4.9 exit code follows the missing count" "$WANT_RC" "$RC"
assert_eq "4.10 the claude version check passes against the stub" 1 "$(okl '^ok claude version 2.1.318$')"
# GAP counts only the two check 7 outcomes a bare main checkout causes: no pin, no pin prefix. It
# does not count an invalid pin (not an executable file, or an unapproved major), because folding
# that into GAP would let a broken pin pass 4.6 and 4.8. This block checks the pin only when one
# is set, and reports nothing when the main checkout holds no pin yet.
PIN="$(jq -r '.env.CLAUDE_CODE_SHELL // empty' "$H/.claude/settings.json")"
if [ -n "$PIN" ]; then
	assert_eq "4.11 the set pin is an executable approved bash" 1 "$(okl "^ok harness bash $PIN ")"
fi

echo "--- 5. the CI step runs this stream's suites on bash 3.2"
STEP_SUITES="test-brew-sync test-maintenance-check test-install-bashrc test-install-hostkeys test-bootstrap-doctor test-no-stale-refs test-install-fresh-home"
# shellcheck disable=SC2016 # \$ is a regular-expression escape for a literal dollar sign
assert_eq "5.1 the workflow runs suites with /bin/bash" 1 "$(grep -c '/bin/bash "tests/\$t\.sh"' "$WORKFLOW")"
# Suites start bare `bash` for the hook or the installer. Homebrew bash leads PATH on the runner, so
# the step puts /bin (bash 3.2) first, or those subprocesses would run Homebrew bash.
# shellcheck disable=SC2016 # \$ is a regular-expression escape for a literal dollar sign
assert_eq "5.2 the workflow puts /bin first on PATH for those suites" 1 "$(grep -c 'PATH="/bin:\$PATH"' "$WORKFLOW")"
for s in $STEP_SUITES; do
	assert_eq "5.$s is listed in the workflow" 1 "$(grep -c "$s" "$WORKFLOW")"
	assert_eq "5.$s exists" yes "$([ -f "$REPO_DIR/tests/$s.sh" ] && echo yes || echo no)"
done

echo "--- 6. the old CLAUDE.md link"
# Decision D-003: the repo has no CLAUDE.md. Old installs linked one into ~/.claude, and Claude Code
# reads that path. install.sh removes the link only when its target ends in
# /anaiis-dotfiles/claude/CLAUDE.md. A real file or a link to another target stays, and the run says so.
run_links() {
	OUT="$(HOME="$1" PATH="$TMPD/stub:$PATH" "$BASH" "${2:-$INSTALL}" --symlinks-only 2>&1)"
	RC=$?
}
mentions() { printf '%s\n' "$OUT" | grep -c 'CLAUDE\.md'; }

# The stale-link case needs a canonical folder that has rules/context.md (see section 7). The main
# checkout lacks that file when it is older than the installer, so the case uses a fixture folder.
FX6="$TMPD/fx6"
mkdir -p "$FX6/claude/rules"
cp "$INSTALL" "$FX6/install.sh"
printf 'context\n' >"$FX6/claude/rules/context.md"
H6="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$H6/.claude"
ln -s "$H6/anaiis-dotfiles/claude/CLAUDE.md" "$H6/.claude/CLAUDE.md"
run_links "$H6" "$FX6/install.sh"
assert_eq "6.1 stale link: exit code is 0" 0 "$RC"
assert_eq "6.2 stale link: the link is removed" no \
	"$([ -L "$H6/.claude/CLAUDE.md" ] || [ -e "$H6/.claude/CLAUDE.md" ] && echo yes || echo no)"
assert_eq "6.3 stale link: one unlink line names the link" 1 "$(printf '%s\n' "$OUT" | grep -c "^  unlink $H6/.claude/CLAUDE.md ")"
assert_eq "6.4 stale link: the other links are still made" yes \
	"$([ -L "$H6/.claude/settings.json" ] && [ -L "$H6/.claude/rules" ] && echo yes || echo no)"
SNAP6="$(snapshot "$H6")"
run_links "$H6" "$FX6/install.sh"
assert_eq "6.5 second run: exit code is 0" 0 "$RC"
assert_eq "6.6 second run: no line mentions CLAUDE.md" 0 "$(mentions)"
assert_eq "6.7 second run: no change line" 0 "$(printf '%s\n' "$OUT" | grep -cE "$CHANGE_RE")"
assert_eq "6.8 second run: the HOME snapshot is identical" "$SNAP6" "$(snapshot "$H6")"

H6="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$H6/.claude"
printf 'mine\n' >"$H6/.claude/CLAUDE.md"
run_links "$H6"
assert_eq "6.9 real file: exit code is 0" 0 "$RC"
assert_eq "6.10 real file: the file and its text stay" mine "$(cat "$H6/.claude/CLAUDE.md")"
assert_eq "6.11 real file: the run prints one note about it" 1 "$(printf '%s\n' "$OUT" | grep -c '^  note  .*CLAUDE\.md is a real file')"

H6="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$H6/.claude" "$H6/elsewhere"
printf 'other\n' >"$H6/elsewhere/CLAUDE.md"
ln -s "$H6/elsewhere/CLAUDE.md" "$H6/.claude/CLAUDE.md"
run_links "$H6"
assert_eq "6.12 link elsewhere: exit code is 0" 0 "$RC"
assert_eq "6.13 link elsewhere: the link target is unchanged" "$H6/elsewhere/CLAUDE.md" "$(readlink "$H6/.claude/CLAUDE.md")"
assert_eq "6.14 link elsewhere: the target file stays" other "$(cat "$H6/elsewhere/CLAUDE.md")"
assert_eq "6.15 link elsewhere: the run prints one note about it" 1 "$(printf '%s\n' "$OUT" | grep -c '^  note  .*CLAUDE\.md is a link to ')"

echo "--- 7. the old CLAUDE.md link stays until its replacement exists"
# install.sh resolves the main checkout as canonical, and that checkout can be older than the installer
# (for example, the installer runs from a linked worktree). A copy of install.sh in a folder outside any
# git repo makes that folder canonical, so the test controls whether claude/rules/context.md exists there.
FX7="$TMPD/fx7"
mkdir -p "$FX7/claude/rules"
cp "$INSTALL" "$FX7/install.sh"
H7="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$H7/.claude"
ln -s "$H7/anaiis-dotfiles/claude/CLAUDE.md" "$H7/.claude/CLAUDE.md"
run_links "$H7" "$FX7/install.sh"
assert_eq "7.1 no context.md: exit code is 0" 0 "$RC"
assert_eq "7.2 no context.md: the link stays" "$H7/anaiis-dotfiles/claude/CLAUDE.md" "$(readlink "$H7/.claude/CLAUDE.md")"
assert_eq "7.3 no context.md: no unlink line" 0 "$(printf '%s\n' "$OUT" | grep -c '^  unlink ')"
assert_eq "7.4 no context.md: one note names context.md" 1 "$(printf '%s\n' "$OUT" | grep -c '^  note  .*CLAUDE\.md kept: .*context\.md is missing')"
assert_eq "7.5 no context.md: the other links are still made" yes \
	"$([ -L "$H7/.claude/settings.json" ] && [ -L "$H7/.claude/rules" ] && echo yes || echo no)"
printf 'context\n' >"$FX7/claude/rules/context.md"
run_links "$H7" "$FX7/install.sh"
assert_eq "7.6 context.md added, run again: exit code is 0" 0 "$RC"
assert_eq "7.7 context.md added, run again: the link is removed" no \
	"$([ -L "$H7/.claude/CLAUDE.md" ] || [ -e "$H7/.claude/CLAUDE.md" ] && echo yes || echo no)"
assert_eq "7.8 context.md added, run again: one unlink line names the link" 1 "$(printf '%s\n' "$OUT" | grep -c "^  unlink $H7/.claude/CLAUDE.md ")"

echo "--- 8. a memory link becomes a local folder with the same data"
# The repo stops tracking claude/memory/. After that, a git pull deletes the data behind a link, so
# install.sh copies the data into a real folder and then removes the link. It never deletes data.
H8="$(mktemp -d "$TMPD/home.XXXXXX")"
SRC8="$TMPD/fx8-memory"
mkdir -p "$H8/.claude" "$SRC8"
printf '# Global Memory Index\n\n- [Profile](user_profile.md): fixture\n' >"$SRC8/MEMORY.md"
printf -- '---\nname: user-profile\ndescription: fixture\ntype: user\n---\n\nfixture body\n' >"$SRC8/user_profile.md"
ln -s "$SRC8" "$H8/.claude/memory"
run_links "$H8"
assert_eq "8.1 link: exit code is 0" 0 "$RC"
assert_eq "8.2 link: the path is now a real folder" yes \
	"$([ -d "$H8/.claude/memory" ] && [ ! -L "$H8/.claude/memory" ] && echo yes || echo no)"
assert_eq "8.3 link: the folder holds the same files, byte for byte" "" "$(diff -r "$SRC8" "$H8/.claude/memory" 2>&1)"
assert_eq "8.5 link: the old target keeps its two files" 2 "$(find "$SRC8" -mindepth 1 | wc -l | tr -d ' ')"
assert_eq "8.6 link: one migrated line names the path" 1 "$(printf '%s\n' "$OUT" | grep -c "^  migrated $H8/.claude/memory ")"
assert_eq "8.7 link: no temp folder is left next to it" "" "$(find "$H8/.claude" -maxdepth 1 -name 'memory.*')"
SNAP8="$(snapshot "$H8")"
run_links "$H8"
assert_eq "8.8 second run: exit code is 0" 0 "$RC"
assert_eq "8.9 second run: one ok line for the local folder" 1 \
	"$(printf '%s\n' "$OUT" | grep -c "^  ok   $H8/.claude/memory (local folder)$")"
assert_eq "8.10 second run: no change line" 0 "$(printf '%s\n' "$OUT" | grep -cE "$CHANGE_RE")"
assert_eq "8.11 second run: the HOME snapshot is identical" "$SNAP8" "$(snapshot "$H8")"

echo "--- 9. a dangling memory link"
# The data is gone, so install.sh cannot copy it. It writes an empty index and names the git command
# that recovers the old files.
H9="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$H9/.claude"
ln -s "$TMPD/no-such-memory" "$H9/.claude/memory"
run_links "$H9"
assert_eq "9.1 dangling: exit code is 0" 0 "$RC"
assert_eq "9.2 dangling: the path is now a real folder" yes \
	"$([ -d "$H9/.claude/memory" ] && [ ! -L "$H9/.claude/memory" ] && echo yes || echo no)"
assert_eq "9.3 dangling: the folder holds only the empty MEMORY.md index" "MEMORY.md" "$(cd "$H9/.claude/memory" && find . -mindepth 1 | sed 's|^\./||' 2>&1)"
assert_eq "9.4 dangling: one WARN line names the recovery command" 1 \
	"$(printf '%s\n' "$OUT" | grep -c "^  WARN $H9/.claude/memory .*git -C .* archive .*claude/memory")"

H9="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$H9/.claude"
printf 'mine\n' >"$H9/.claude/memory"
run_links "$H9"
assert_eq "9.5 a regular file: exit code is 0" 0 "$RC"
assert_eq "9.6 a regular file: the file and its text stay" mine "$(cat "$H9/.claude/memory")"
assert_eq "9.7 a regular file: one SKIP line names it" 1 "$(printf '%s\n' "$OUT" | grep -c "^  SKIP $H9/.claude/memory ")"

echo "--- 10. a link to another folder is replaced, not followed"
# Without ln -n, ln follows a link to a folder and makes a stray link inside that folder
# (an integration run made claude/rules/rules in a worktree this way).
H10="$(mktemp -d "$TMPD/home.XXXXXX")"
OTHER10="$(mktemp -d "$TMPD/other.XXXXXX")"
mkdir -p "$H10/.claude"
ln -s "$OTHER10" "$H10/.claude/rules"
run_links "$H10"
assert_eq "10.1 exit code is 0" 0 "$RC"
assert_eq "10.2 ~/.claude/rules now resolves into the main checkout" "$MAIN/claude/rules" "$(cd "$H10/.claude/rules" && pwd -P)"
assert_eq "10.3 the other folder holds no new entry" "" "$(ls -A "$OTHER10")"

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$INSTALL" "$DOCTOR"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
