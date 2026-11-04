#!/usr/bin/env bash
# tests/test-bootstrap-doctor.sh -- verify claude/scripts/bootstrap-doctor.sh.
#
# Why this matters: on the first fresh machine the install looked fine, but plugins were not
# loaded because of a missing GitHub host key, and nothing said so. The doctor lists each gap with
# the command that fixes it. A doctor that reports ok on a broken machine, or that changes the
# machine it inspects, is worse than none.
#
# Method: each case builds a throwaway HOME that is healthy, breaks exactly one thing, and expects
# exactly one MISSING line. The doctor runs with a PATH that holds only the tools it may use, so the
# real gh and the real Homebrew never answer. A stub gh answers `config get git_protocol`.
#
# Env override, used for the fail-to-fail check:
#   DOCTOR   path of the script under test
#
# Usage: bash tests/test-bootstrap-doctor.sh        (COV=1 adds line coverage on bash 4.1 or later)

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="${DOCTOR:-$REPO_DIR/claude/scripts/bootstrap-doctor.sh}"

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

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/test-bootstrap-doctor.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

if [ -n "${COV:-}" ]; then
	# shellcheck source-path=SCRIPTDIR
	# shellcheck source=lib/cov.sh
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$TMPD/cov.log"
fi

# ---- Tools on PATH ----------------------------------------------------------
# The doctor may call only: dirname basename readlink grep jq gh ssh-keygen. Each PATH folder below
# links just those that a case needs. Without gh or jq on PATH, the doctor sees them as absent.
mkdir -p "$TMPD/stub"
cat >"$TMPD/stub/gh" <<'EOF'
#!/bin/sh
# POSIX sh, not env bash: the doctor runs with a PATH that holds no env and no bash.
# Accepts exactly: config get git_protocol. STUB_PROTOCOL empty means the key is unset.
[ "$*" = "config get git_protocol" ] || {
	echo "stub gh: unexpected arguments: $*" >&2
	exit 64
}
[ -n "${STUB_PROTOCOL:-}" ] || exit 1
echo "$STUB_PROTOCOL"
EOF
chmod +x "$TMPD/stub/gh"

# make_bin <dir> <tool>...: a PATH folder that links the named real tools. The stub gh is "gh".
make_bin() {
	local dir="$1" tool real
	shift
	mkdir -p "$dir"
	for tool in "$@"; do
		if [ "$tool" = gh ]; then
			real="$TMPD/stub/gh"
		else
			real="$(command -v "$tool")"
		fi
		ln -s "$real" "$dir/$tool"
	done
}
make_bin "$TMPD/bin" dirname basename readlink grep jq ssh-keygen gh
make_bin "$TMPD/bin-nogh" dirname basename readlink grep jq ssh-keygen
make_bin "$TMPD/bin-nojq" dirname basename readlink grep ssh-keygen gh

# ---- Fixture HOME -----------------------------------------------------------
ssh-keygen -q -t ed25519 -N '' -C '' -f "$TMPD/hostkey" >/dev/null
KEYTEXT="$(awk '{print $1, $2}' "$TMPD/hostkey.pub")"
SETTINGS_JSON='{"enabledPlugins": {"alpha@mk1": true, "beta@mk2": true, "off@mk3": false}}'
NAMES="settings.json keybindings.json rules commands skills agents hooks scripts memory"

# build_home: print the path of a new, healthy HOME. The repo sits elsewhere and ~/anaiis-dotfiles
# links to it, as install.sh arranges when the clone is not at the canonical path.
build_home() {
	local h repo name
	h="$(mktemp -d "$TMPD/home.XXXXXX")"
	repo="$h.repo"
	mkdir -p "$repo/claude" "$h/.claude" "$h/.ssh"
	for name in rules commands skills agents hooks scripts memory; do
		mkdir -p "$repo/claude/$name"
	done
	printf '%s\n' "$SETTINGS_JSON" >"$repo/claude/settings.json"
	printf '{}\n' >"$repo/claude/keybindings.json"
	ln -s "$repo" "$h/anaiis-dotfiles"
	for name in $NAMES; do
		ln -s "$h/anaiis-dotfiles/claude/$name" "$h/.claude/$name"
	done
	mkdir -p "$h/.claude/plugins/cache/mk1/alpha" "$h/.claude/plugins/cache/mk2/beta"
	# shellcheck disable=SC2016 # $HOME stays literal: these are the lines that install.sh writes
	printf '# mine\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\nsource "$HOME/anaiis-dotfiles/bash/shared.bash"\n' >"$h/.bashrc"
	# shellcheck disable=SC2016 # $HOME stays literal
	printf '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >"$h/.bash_profile"
	printf 'github.com %s\n' "$KEYTEXT" >"$h/.ssh/known_hosts"
	printf '%s\n' "$h"
}

# doctor <home>: run the script. OUT holds stdout and stderr, RC the exit code.
# PROTO (default ssh) sets the stub gh answer; BIN_DIR (default $TMPD/bin) sets PATH.
doctor() {
	OUT="$(HOME="$1" PATH="${BIN_DIR:-$TMPD/bin}" STUB_PROTOCOL="${PROTO-ssh}" "$BASH" "$DOCTOR" 2>&1)"
	RC=$?
}

# snapshot <home>: one checksum over the sorted paths, the file contents, and the link targets.
snapshot() {
	(
		cd "$1" || exit 1
		{
			find . | LC_ALL=C sort
			find . -type f -exec cksum {} + | LC_ALL=C sort
			find . -type l -exec readlink {} \; | LC_ALL=C sort
		} | cksum
	)
}

miss_lines() { printf '%s\n' "$OUT" | grep '^MISSING ' || true; }
miss_count() { printf '%s\n' "$OUT" | grep -c '^MISSING ' || true; }
ok_count() { printf '%s\n' "$OUT" | grep -c '^ok ' || true; }

# expect_one <name> <home> <expected MISSING line>: the doctor reports exactly that one gap.
expect_one() {
	doctor "$2"
	assert_eq "$1: exit code 1" 1 "$RC"
	assert_eq "$1: the one MISSING line" "$3" "$(miss_lines)"
	assert_eq "$1: summary line" "doctor: 1 missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
}

FIX_BASHRC='bash ~/anaiis-dotfiles/install.sh --bashrc-only'
FIX_LINKS='bash ~/anaiis-dotfiles/install.sh --symlinks-only'
FIX_KEYS='bash ~/anaiis-dotfiles/install.sh --hostkeys-only'
FIX_PLUGIN='start Claude Code once, run /reload-plugins, and read the /plugin Errors tab. A GitHub clone over SSH needs the host key from the github.com check (fix: bash ~/anaiis-dotfiles/install.sh --hostkeys-only).'
# shellcheck disable=SC2016 # $HOME stays literal: it is the text that the doctor prints
FIX_LOGIN='add this line to it: [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'

echo "--- 0. a healthy HOME"
H0="$(build_home)"
SNAP0="$(snapshot "$H0")"
doctor "$H0"
assert_eq "0.1 exit code 0" 0 "$RC"
assert_eq "0.2 no MISSING line" 0 "$(miss_count)"
assert_eq "0.3 summary line" "doctor: 0 missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
# 2 bashrc + 1 login + 9 links + 2 enabled plugins + 1 host key. The disabled plugin is not listed.
assert_eq "0.4 fifteen ok lines" 15 "$(ok_count)"
assert_eq "0.5 the disabled plugin is not checked" 0 "$(printf '%s\n' "$OUT" | grep -c 'off@mk3' || true)"
assert_eq "0.6 the HOME is unchanged" "$SNAP0" "$(snapshot "$H0")"

echo "--- 1. shell config"
H="$(build_home)"
rm "$H/.bashrc"
expect_one "1.1 no .bashrc" "$H" "MISSING ~/.bashrc (absent): $FIX_BASHRC"
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '# mine\nsource "$HOME/anaiis-dotfiles/bash/shared.bash"\n' >"$H/.bashrc"
expect_one "1.2 no PATH line" "$H" "MISSING ~/.bashrc PATH line: $FIX_BASHRC"
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '# mine\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\n' >"$H/.bashrc"
expect_one "1.3 no shared.bash line" "$H" "MISSING ~/.bashrc shared.bash line: $FIX_BASHRC"
# A commented-out line loads nothing, so it must not count (the shell never reads it).
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '# mine\n# export PATH="$HOME/anaiis-dotfiles/bin:$PATH"\nsource "$HOME/anaiis-dotfiles/bash/shared.bash"\n' >"$H/.bashrc"
expect_one "1.4 a commented-out PATH line does not count" "$H" "MISSING ~/.bashrc PATH line: $FIX_BASHRC"
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '# mine\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\n  # source "$HOME/anaiis-dotfiles/bash/shared.bash"\n' >"$H/.bashrc"
expect_one "1.5 an indented, commented-out shared.bash line does not count" "$H" \
	"MISSING ~/.bashrc shared.bash line: $FIX_BASHRC"
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '# mine\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH" # tools\nsource "$HOME/anaiis-dotfiles/bash/shared.bash" # prompt\n' >"$H/.bashrc"
doctor "$H"
assert_eq "1.6 active lines that end in a comment still count: exit 0" 0 "$RC"

echo "--- 2. login shell file"
H="$(build_home)"
rm "$H/.bash_profile"
expect_one "2.1 no login file" "$H" \
	"MISSING login shell file (no ~/.bash_profile, ~/.bash_login, or ~/.profile): $FIX_BASHRC"
H="$(build_home)"
printf 'export EDITOR=vi\n' >"$H/.bash_profile"
expect_one "2.2 .bash_profile never mentions .bashrc" "$H" \
	"MISSING ~/.bash_profile (never mentions ~/.bashrc): $FIX_LOGIN"
H="$(build_home)"
rm "$H/.bash_profile"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >"$H/.profile"
doctor "$H"
assert_eq "2.3 a .profile that sources .bashrc is enough when .bash_profile is absent: exit 0" 0 "$RC"
assert_eq "2.4 the ok line names the file that bash reads" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok ~/.profile mentions ~/.bashrc')"
H="$(build_home)"
rm "$H/.bash_profile"
printf 'export EDITOR=vi\n' >"$H/.bash_login"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >"$H/.profile"
expect_one "2.5 bash reads .bash_login first, so a good .profile does not count" "$H" \
	"MISSING ~/.bash_login (never mentions ~/.bashrc): $FIX_LOGIN"
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf '# [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >"$H/.bash_profile"
expect_one "2.6 a commented-out .bashrc line does not count" "$H" \
	"MISSING ~/.bash_profile (never mentions ~/.bashrc): $FIX_LOGIN"
# A file that sources only ~/.bashrc.local never loads ~/.bashrc in a login shell. A file whose
# name only starts with .bashrc is not .bashrc.
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
for line in 'source "$HOME/.bashrc.local"' '. ~/.bashrc_old' '[ -f ~/.bashrc.bak ] && . ~/.bashrc.bak'; do
	H="$(build_home)"
	printf '%s\n' "$line" >"$H/.bash_profile"
	expect_one "2.7 only '$line' does not count" "$H" \
		"MISSING ~/.bash_profile (never mentions ~/.bashrc): $FIX_LOGIN"
done
# Each real way to source .bashrc still counts, also with a trailing comment.
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
for line in \
	'[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' \
	'source ~/.bashrc' \
	'. ~/.bashrc' \
	'. "${HOME}/.bashrc"' \
	'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi' \
	'[ -r ~/.bashrc ] && source ~/.bashrc # shell config'; do
	H="$(build_home)"
	printf '%s\n' "$line" >"$H/.bash_profile"
	doctor "$H"
	assert_eq "2.8 '$line' counts: exit 0" 0 "$RC"
done
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal in the fixture file
printf 'source "$HOME/.bashrc.local"\n. ~/.bashrc\n' >"$H/.bash_profile"
doctor "$H"
assert_eq "2.9 a .bashrc.local line does not hide a real .bashrc line: exit 0" 0 "$RC"

echo "--- 3. the nine ~/.claude links"
for name in $NAMES; do
	H="$(build_home)"
	rm "$H/.claude/$name"
	if [ "$name" = settings.json ]; then
		# Without settings.json the plugin list is unreadable too: two gaps, one cause.
		doctor "$H"
		assert_eq "3.$name: exit code 1" 1 "$RC"
		assert_eq "3.$name: the link and the plugin list are reported" \
			"MISSING ~/.claude/settings.json (absent): $FIX_LINKS
MISSING plugin list (~/.claude/settings.json absent): $FIX_LINKS" "$(miss_lines)"
	else
		expect_one "3.$name absent" "$H" "MISSING ~/.claude/$name (absent): $FIX_LINKS"
	fi
done
H="$(build_home)"
rm "$H/.claude/rules"
mkdir "$H/.claude/rules"
expect_one "3.10 a real folder instead of a link" "$H" "MISSING ~/.claude/rules (not a link): $FIX_LINKS"
H="$(build_home)"
rm "$H/.claude/hooks"
ln -s "$H/no-such-target" "$H/.claude/hooks"
expect_one "3.11 a dangling link" "$H" "MISSING ~/.claude/hooks (dangling): $FIX_LINKS"
H="$(build_home)"
rm "$H/.claude/skills"
mkdir -p "$TMPD/elsewhere/skills"
ln -s "$TMPD/elsewhere/skills" "$H/.claude/skills"
expect_one "3.12 a link that points outside the repo" "$H" \
	"MISSING ~/.claude/skills (points outside ~/anaiis-dotfiles/claude): $FIX_LINKS"

H="$(build_home)"
rm "$H/.claude/commands"
ln -s ../anaiis-dotfiles/claude/commands "$H/.claude/commands"
doctor "$H"
assert_eq "3.13 a relative link into the repo is accepted: exit 0" 0 "$RC"
assert_eq "3.14 a relative link into the repo is reported ok" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok ~/.claude/commands ')"

# A link must reach its own target. The installer gives each name one target, so a link to another
# folder of the same repo is wrong even though it sits inside the repo.
H="$(build_home)"
rm "$H/.claude/rules"
ln -s "$H/anaiis-dotfiles/claude/hooks" "$H/.claude/rules"
expect_one "3.15 a link to another folder of the repo" "$H" \
	"MISSING ~/.claude/rules (points to the wrong place, expected ~/anaiis-dotfiles/claude/rules): $FIX_LINKS"

echo "--- 4. plugins"
H="$(build_home)"
rm -r "$H/.claude/plugins/cache/mk1/alpha"
expect_one "4.1 a plugin folder is absent" "$H" "MISSING plugin alpha@mk1: $FIX_PLUGIN"
H="$(build_home)"
printf '{"enabledPlugins": {"alpha@mk1": ' >"$H/anaiis-dotfiles/claude/settings.json"
expect_one "4.2 settings.json is not valid JSON" "$H" \
	"MISSING plugin list (~/.claude/settings.json is not valid JSON): repair the file, then run this script again"
H="$(build_home)"
printf '{"enabledPlugins": {}}\n' >"$H/anaiis-dotfiles/claude/settings.json"
doctor "$H"
assert_eq "4.3 no enabled plugin: exit 0" 0 "$RC"
assert_eq "4.4 an ok line says none are enabled" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok plugins (none enabled)')"
H="$(build_home)"
BIN_DIR="$TMPD/bin-nojq" expect_one "4.5 jq is not installed" "$H" "MISSING jq (needed to read the plugin list): brew install jq"

echo "--- 5. GitHub host key"
H="$(build_home)"
rm "$H/.ssh/known_hosts"
expect_one "5.1 ssh protocol and no host key" "$H" "MISSING github.com host key (~/.ssh/known_hosts): $FIX_KEYS"
H="$(build_home)"
printf 'example.org %s\n' "$KEYTEXT" >"$H/.ssh/known_hosts"
expect_one "5.2 ssh protocol and a known_hosts file without github.com" "$H" \
	"MISSING github.com host key (~/.ssh/known_hosts): $FIX_KEYS"
H="$(build_home)"
rm "$H/.ssh/known_hosts"
PROTO=https doctor "$H"
assert_eq "5.3 https protocol: exit 0 without a host key" 0 "$RC"
assert_eq "5.4 https protocol: the ok line says it is not needed" 1 \
	"$(printf '%s\n' "$OUT" | grep -c '^ok github.com host key (not needed: gh protocol is https)')"
PROTO="" doctor "$H"
assert_eq "5.5 unset protocol: exit 0" 0 "$RC"
assert_eq "5.6 unset protocol: the ok line says so" 1 \
	"$(printf '%s\n' "$OUT" | grep -c '^ok github.com host key (not needed: gh protocol is unset)')"
BIN_DIR="$TMPD/bin-nogh" doctor "$H"
assert_eq "5.7 no gh: exit 0 without a host key" 0 "$RC"
assert_eq "5.8 no gh: the ok line says so" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok github.com host key (not needed: gh not found)')"

echo "--- 6. a fresh HOME reports every gap and changes nothing"
HF="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$HF/.claude"
SNAPF="$(snapshot "$HF")"
doctor "$HF"
assert_eq "6.1 exit code 1" 1 "$RC"
# 1 bashrc + 1 login + 9 links + 1 plugin list + 1 host key
assert_eq "6.2 thirteen MISSING lines" 13 "$(miss_count)"
assert_eq "6.3 summary counts the same gaps" "doctor: 13 missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
assert_eq "6.4 the HOME is unchanged" "$SNAPF" "$(snapshot "$HF")"

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$DOCTOR"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
