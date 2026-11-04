#!/usr/bin/env bash
# tests/test-install-fresh-home.sh -- end to end: the real install.sh, in full mode, run twice
# against a HOME that starts empty.
#
# Why this matters: a new machine must reach a working harness with one command and no manual
# repair. The first run must not abort (SC-1). The second run must change nothing and must not
# print a link, add, created, updated, or migrated line (SC-2). Then bootstrap-doctor.sh must
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
CHANGE_RE='^  (link|add|created|updated|migrated)( |$)'

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
assert_eq "3.2 no line starts with link, add, created, updated, or migrated" 0 \
	"$(printf '%s\n' "$OUT" | grep -cE "$CHANGE_RE")"
assert_eq "3.3 the HOME snapshot is identical" "$SNAP1" "$(snapshot "$H")"
assert_eq "3.4 the second run ends with Done." 1 "$(printf '%s\n' "$OUT" | grep -c '^Done\.$')"

echo "--- 4. the doctor agrees"
ENABLED="$(jq '[(.enabledPlugins // {}) | to_entries[] | select(.value == true)] | length' "$H/.claude/settings.json")"
OUT="$(HOME="$H" PATH="$TMPD/stub:$PATH" "$BASH" "$DOCTOR" 2>&1)"
RC=$?
okl() { printf '%s\n' "$OUT" | grep -c "$1"; }
assert_eq "4.1 ok for the PATH line" 1 "$(okl '^ok ~/.bashrc PATH line$')"
assert_eq "4.2 ok for the shared.bash line" 1 "$(okl '^ok ~/.bashrc shared.bash line$')"
assert_eq "4.3 ok for the login shell file" 1 "$(okl '^ok ~/.bash_profile mentions ~/.bashrc$')"
assert_eq "4.4 ok for all nine links" 9 "$(okl '^ok ~/.claude/[a-z.]* -> ~/anaiis-dotfiles/claude$')"
assert_eq "4.5 one MISSING line per enabled plugin" "$ENABLED" "$(okl '^MISSING plugin ')"
assert_eq "4.6 no other MISSING line" "$ENABLED" "$(okl '^MISSING ')"
assert_eq "4.7 the host key is not needed for https" 1 "$(okl '^ok github.com host key (not needed: gh protocol is https)$')"
assert_eq "4.8 summary counts the missing plugins" "doctor: $ENABLED missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
if [ "$ENABLED" -gt 0 ]; then WANT_RC=1; else WANT_RC=0; fi
assert_eq "4.9 exit code follows the missing count" "$WANT_RC" "$RC"

echo "--- 5. the CI step runs this stream's suites on bash 3.2"
STEP_SUITES="test-brew-sync test-maintenance-check test-install-bashrc test-install-hostkeys test-bootstrap-doctor test-no-stale-refs test-install-fresh-home"
# shellcheck disable=SC2016 # \$ is a regular-expression escape for a literal dollar sign
assert_eq "5.1 the workflow runs suites with /bin/bash" 1 "$(grep -c '/bin/bash "tests/\$t\.sh"' "$WORKFLOW")"
for s in $STEP_SUITES; do
	assert_eq "5.$s is listed in the workflow" 1 "$(grep -c "$s" "$WORKFLOW")"
	assert_eq "5.$s exists" yes "$([ -f "$REPO_DIR/tests/$s.sh" ] && echo yes || echo no)"
done

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$INSTALL" "$DOCTOR"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
