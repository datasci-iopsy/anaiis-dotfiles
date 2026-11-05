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

# The approved bash majors are the one line APPROVED_BASH_MAJORS in the doctor. The stub bash prints the
# first approved major by default, and the wrong-major cases use one below and one above the list. An
# older doctor has no such line: the check 7 cases then fail, as they must.
APPROVED="$(sed -n 's/^APPROVED_BASH_MAJORS="\(.*\)"$/\1/p' "$DOCTOR")"
APPROVED="${APPROVED:-5}"
FIRST=""
LOW=""
HIGH=""
for m in $APPROVED; do
	[ -n "$FIRST" ] || {
		FIRST="$m"
		LOW=$((m - 1))
	}
	HIGH=$((m + 1))
done

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
# The doctor may call only: dirname basename readlink grep jq gh ssh-keygen claude sqlfmt. Each PATH folder
# below links just those that a case needs. Without gh, jq, or claude on PATH, the doctor sees them as absent.
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
cat >"$TMPD/stub/claude" <<'EOF'
#!/bin/sh
# POSIX sh, for the same reason as the stub gh. Accepts exactly: --version.
# STUB_CLAUDE_VERSION is the whole line to print. It may be empty. The doctor always sets it.
[ "$*" = "--version" ] || {
	echo "stub claude: unexpected arguments: $*" >&2
	exit 64
}
echo "$STUB_CLAUDE_VERSION"
EOF
chmod +x "$TMPD/stub/claude"
cat >"$TMPD/stub/bash" <<'EOF'
#!/bin/sh
# POSIX sh, for the same reason as the stub gh. The pin in the fixture settings.json points here by
# absolute path. Accepts exactly: -c <script>. The doctor asks for the major version of bash.
# STUB_BASH_V is the major to print. It may be empty. The doctor always sets it.
[ "$1" = "-c" ] || {
	echo "stub bash: unexpected arguments: $*" >&2
	exit 64
}
printf '%s' "$STUB_BASH_V"
EOF
chmod +x "$TMPD/stub/bash"
cat >"$TMPD/stub/sqlfmt" <<'EOF'
#!/bin/sh
# POSIX sh, for the same reason as the stub gh. Accepts exactly: --version.
# STUB_SQLFMT_V is the whole line to print. Empty makes it fail, like a broken install.
[ "$*" = "--version" ] || {
	echo "stub sqlfmt: unexpected arguments: $*" >&2
	exit 64
}
[ -n "$STUB_SQLFMT_V" ] || exit 1
echo "$STUB_SQLFMT_V"
EOF
chmod +x "$TMPD/stub/sqlfmt"

# make_bin <dir> <tool>...: a PATH folder that links the named real tools. The stubs are "gh", "claude", and "sqlfmt".
make_bin() {
	local dir="$1" tool real
	shift
	mkdir -p "$dir"
	for tool in "$@"; do
		if [ "$tool" = gh ] || [ "$tool" = claude ] || [ "$tool" = sqlfmt ]; then
			real="$TMPD/stub/$tool"
		else
			real="$(command -v "$tool")"
		fi
		ln -s "$real" "$dir/$tool"
	done
}
make_bin "$TMPD/bin" dirname basename readlink grep jq ssh-keygen gh claude sqlfmt
make_bin "$TMPD/bin-nogh" dirname basename readlink grep jq ssh-keygen claude sqlfmt
make_bin "$TMPD/bin-nojq" dirname basename readlink grep ssh-keygen gh claude sqlfmt
make_bin "$TMPD/bin-noclaude" dirname basename readlink grep jq ssh-keygen gh sqlfmt
make_bin "$TMPD/bin-nosqlfmt" dirname basename readlink grep jq ssh-keygen gh claude

# ---- Fixture HOME -----------------------------------------------------------
ssh-keygen -q -t ed25519 -N '' -C '' -f "$TMPD/hostkey" >/dev/null
KEYTEXT="$(awk '{print $1, $2}' "$TMPD/hostkey.pub")"
# A healthy settings.json: two enabled plugins and one disabled, a pin to the stub bash, and two
# commands (a hook and the status line) that start with the pin prefix.
STUB_PIN="$TMPD/stub/bash"
# shellcheck disable=SC2016 # ${...} stays literal: it is the text that settings.json holds
SETTINGS_JSON="$(jq -cn --arg pin "$STUB_PIN" --arg cmd '${CLAUDE_CODE_SHELL:-bash} $HOME/.claude/hooks/a.sh' '{
	enabledPlugins: {"alpha@mk1": true, "beta@mk2": true, "off@mk3": false},
	env: {CLAUDE_CODE_SHELL: $pin},
	hooks: {Stop: [{hooks: [{type: "command", command: $cmd}]}]},
	statusLine: {type: "command", command: $cmd}}')"
NAMES="settings.json keybindings.json rules commands skills agents hooks scripts"

# build_home: print the path of a new, healthy HOME. The repo sits elsewhere and ~/anaiis-dotfiles
# links to it, as install.sh arranges when the clone is not at the canonical path. ~/.claude/memory is
# a real folder, as install.sh leaves it. The doctor does not read its files.
build_home() {
	local h repo name
	h="$(mktemp -d "$TMPD/home.XXXXXX")"
	repo="$h.repo"
	mkdir -p "$repo/claude" "$h/.claude/memory" "$h/.ssh"
	for name in rules commands skills agents hooks scripts; do
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
# CLAUDE_V (default: a new version) sets the line that the stub claude prints for --version.
# SQLFMT_V (default: version 0.32.0) sets the line that the stub sqlfmt prints. Empty makes it fail.
doctor() {
	OUT="$(HOME="$1" PATH="${BIN_DIR:-$TMPD/bin}" STUB_PROTOCOL="${PROTO-ssh}" \
		STUB_CLAUDE_VERSION="${CLAUDE_V-2.1.318 (Claude Code)}" STUB_BASH_V="${STUB_BASH_V-$FIRST}" STUB_SQLFMT_V="${SQLFMT_V-sqlfmt, version 0.32.0}" "$BASH" "$DOCTOR" 2>&1)"
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
# 2 bashrc + 1 login + 8 links + 1 memory folder + 2 enabled plugins + 1 host key + 1 claude version
# + 1 harness bash pin + 1 hook command prefix + 1 sqlfmt. The disabled plugin is not listed.
assert_eq "0.4 nineteen ok lines" 19 "$(ok_count)"
assert_eq "0.5 the disabled plugin is not checked" 0 "$(printf '%s\n' "$OUT" | grep -c 'off@mk3' || true)"
assert_eq "0.6 the HOME is unchanged" "$SNAP0" "$(snapshot "$H0")"
assert_eq "0.7 a real memory folder is ok" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok ~/.claude/memory (local folder)$' || true)"
assert_eq "0.8 no WARN line" 0 "$(printf '%s\n' "$OUT" | grep -c '^WARN ' || true)"

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

echo "--- 3. the eight ~/.claude links"
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
jq -n --arg pin "$STUB_PIN" '{enabledPlugins: {}, env: {CLAUDE_CODE_SHELL: $pin}}' >"$H/anaiis-dotfiles/claude/settings.json"
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

echo "--- 6. Claude Code version"
# onFailure support starts at 2.1.295. Each case below fails a different wrong comparison: a lexical
# compare of the patch (1000 against 295), a compare of the patch alone, or a compare of the minor alone.
FIX_CLAUDE='update Claude Code'
H="$(build_home)"
CLAUDE_V="2.1.294 (Claude Code)" expect_one "6.1 one patch below the minimum" "$H" "MISSING claude version: $FIX_CLAUDE"
CLAUDE_V="2.0.999 (Claude Code)" expect_one "6.2 an older minor with a high patch" "$H" "MISSING claude version: $FIX_CLAUDE"
CLAUDE_V="1.9.9999 (Claude Code)" expect_one "6.3 an older major" "$H" "MISSING claude version: $FIX_CLAUDE"
CLAUDE_V="" expect_one "6.4 the output is empty" "$H" "MISSING claude version: $FIX_CLAUDE"
CLAUDE_V="not a version" expect_one "6.5 the output is not a version" "$H" "MISSING claude version: $FIX_CLAUDE"
CLAUDE_V="2.1 (Claude Code)" expect_one "6.6 the version has two parts" "$H" "MISSING claude version: $FIX_CLAUDE"
CLAUDE_V="2.1.295.1 (Claude Code)" expect_one "6.7 the version has four parts" "$H" "MISSING claude version: $FIX_CLAUDE"
for v in 2.1.295 2.1.1000 2.2.0 3.0.0 2.1.318; do
	CLAUDE_V="$v (Claude Code)" doctor "$H"
	assert_eq "6.8 $v is accepted: exit 0" 0 "$RC"
	assert_eq "6.8 $v is accepted: the ok line names it" 1 "$(printf '%s\n' "$OUT" | grep -c "^ok claude version $v\$")"
done
BIN_DIR="$TMPD/bin-noclaude" doctor "$H"
assert_eq "6.9 no claude: exit 0" 0 "$RC"
assert_eq "6.10 no claude: the ok line says so" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok claude version (not needed: claude not found)')"

echo "--- 7. harness bash (check 7)"
# Why: the harness runs on one approved Homebrew bash major. A pin in settings.json (env.CLAUDE_CODE_SHELL)
# selects the shell of the Bash tool, and every hook command starts with the pin prefix. A lost pin, a
# bash 4, or a bash 6 that nobody approved must show up as a gap. The wrong majors come from
# APPROVED_BASH_MAJORS (see the top of this file), so approving another major needs no edit here.
FIX_PIN='set env.CLAUDE_CODE_SHELL in ~/anaiis-dotfiles/claude/settings.json to the Homebrew bash path, for example /opt/homebrew/bin/bash'
FIX_MAJOR='install an approved bash (brew install bash), or approve this major by editing APPROVED_BASH_MAJORS in ~/anaiis-dotfiles/claude/scripts/bootstrap-doctor.sh'
# shellcheck disable=SC2016 # ${...} stays literal: it is the text that the doctor prints
FIX_PREFIX='start each command in ~/anaiis-dotfiles/claude/settings.json with ${CLAUDE_CODE_SHELL:-bash} (a bare bash follows PATH)'
# edit_settings <home> <jq filter>: rewrite the fixture settings.json.
edit_settings() {
	jq "$2" "$1/anaiis-dotfiles/claude/settings.json" >"$TMPD/edit.json" && mv "$TMPD/edit.json" "$1/anaiis-dotfiles/claude/settings.json"
}

H="$(build_home)"
doctor "$H"
assert_eq "7.1 healthy: the pin line names the path and the major" 1 "$(printf '%s\n' "$OUT" | grep -c "^ok harness bash $STUB_PIN (major $FIRST)\$")"
assert_eq "7.2 healthy: the prefix line counts the commands" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok hook commands start with the pin prefix (2)$')"
H="$(build_home)"
edit_settings "$H" 'del(.env)'
expect_one "7.3 the pin is absent" "$H" "MISSING harness bash pin (env.CLAUDE_CODE_SHELL absent in ~/.claude/settings.json): $FIX_PIN"
H="$(build_home)"
edit_settings "$H" ".env.CLAUDE_CODE_SHELL = \"$TMPD/no-such-bash\""
expect_one "7.4 the pin path is not an executable file" "$H" "MISSING harness bash pin ($TMPD/no-such-bash is not an executable file): $FIX_PIN"
H="$(build_home)"
STUB_BASH_V="$LOW" expect_one "7.5 the pin runs a major below the approved list" "$H" \
	"MISSING harness bash $STUB_PIN (major $LOW, approved: $APPROVED): $FIX_MAJOR"
STUB_BASH_V="$HIGH" expect_one "7.6 the pin runs a major above the approved list" "$H" \
	"MISSING harness bash $STUB_PIN (major $HIGH, approved: $APPROVED): $FIX_MAJOR"
STUB_BASH_V="" expect_one "7.7 the pin prints no major" "$H" \
	"MISSING harness bash $STUB_PIN (major unknown, approved: $APPROVED): $FIX_MAJOR"
H="$(build_home)"
# shellcheck disable=SC2016 # $HOME stays literal: it is the text that settings.json holds
edit_settings "$H" '.hooks.Stop[0].hooks += [{"type": "command", "command": "bash $HOME/.claude/hooks/b.sh"}]'
expect_one "7.8 one of three commands starts with a bare bash" "$H" "MISSING hook commands without the pin prefix (1 of 3): $FIX_PREFIX"
H="$(build_home)"
printf '{"enabledPlugins": {"alpha@mk1": ' >"$H/anaiis-dotfiles/claude/settings.json"
doctor "$H"
assert_eq "7.9 settings.json is not valid JSON: check 7 adds no line to the plugin gap" 1 "$(miss_count)"

echo "--- 8. a fresh HOME reports every gap and changes nothing"
HF="$(mktemp -d "$TMPD/home.XXXXXX")"
mkdir -p "$HF/.claude"
SNAPF="$(snapshot "$HF")"
doctor "$HF"
assert_eq "8.1 exit code 1" 1 "$RC"
# 1 bashrc + 1 login + 8 links + 1 plugin list + 1 host key. Check 7 adds none: no settings.json to read.
assert_eq "8.2 twelve MISSING lines" 12 "$(miss_count)"
assert_eq "8.3 summary counts the same gaps" "doctor: 12 missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
assert_eq "8.4 the HOME is unchanged" "$SNAPF" "$(snapshot "$HF")"
assert_eq "8.5 the absent memory folder is a WARN, not a gap" 1 "$(printf '%s\n' "$OUT" | grep -c '^WARN ~/.claude/memory (absent): ' || true)"

echo "--- 9. the local memory folder"
# The repo stops tracking claude/memory/, so ~/.claude/memory is a real folder on each machine. A new
# machine has no memory yet, so an absent folder is a WARN. A link is the state before install.sh
# converts it, so it is a WARN too. Neither counts as missing.
warn_lines() { printf '%s\n' "$OUT" | grep '^WARN ' || true; }
H="$(build_home)"
rm -r "$H/.claude/memory"
doctor "$H"
assert_eq "9.1 absent: exit code 0" 0 "$RC"
assert_eq "9.2 absent: the one WARN line" "WARN ~/.claude/memory (absent): $FIX_LINKS" "$(warn_lines)"
assert_eq "9.3 absent: summary line" "doctor: 0 missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
H="$(build_home)"
mv "$H/.claude/memory" "$H/anaiis-dotfiles/claude/memory"
ln -s "$H/anaiis-dotfiles/claude/memory" "$H/.claude/memory"
doctor "$H"
assert_eq "9.4 old link: exit code 0" 0 "$RC"
assert_eq "9.5 old link: the one WARN line" "WARN ~/.claude/memory (a link, not a local folder): $FIX_LINKS" "$(warn_lines)"
assert_eq "9.6 old link: no ok line for the folder" 0 "$(printf '%s\n' "$OUT" | grep -c '^ok ~/.claude/memory' || true)"

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$DOCTOR"
fi

echo "--- 10. sqlfmt"
# The post-edit hook and the pre-commit hook skip SQL formatting without sqlfmt, so a gap is a WARN,
# not missing. The doctor looks where the hooks look: PATH, then ~/.local/bin (uv tool install).
FIX_SQLFMT='uv tool install shandy-sqlfmt'
doctor "$H0"
assert_eq "10.1 on PATH: the ok line names the version" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok sqlfmt 0\.32\.0$' || true)"
BIN_DIR="$TMPD/bin-nosqlfmt" doctor "$H0"
assert_eq "10.2 absent: exit code 0" 0 "$RC"
assert_eq "10.3 absent: the one WARN line" "WARN sqlfmt (absent: the hooks skip SQL formatting): $FIX_SQLFMT" "$(warn_lines)"
assert_eq "10.4 absent: summary line" "doctor: 0 missing" "$(printf '%s\n' "$OUT" | tail -n 1)"
H="$(build_home)"
mkdir -p "$H/.local/bin"
ln -s "$TMPD/stub/sqlfmt" "$H/.local/bin/sqlfmt"
BIN_DIR="$TMPD/bin-nosqlfmt" doctor "$H"
assert_eq "10.5 only in ~/.local/bin: the ok line names the version" 1 "$(printf '%s\n' "$OUT" | grep -c '^ok sqlfmt 0\.32\.0$' || true)"
assert_eq "10.6 only in ~/.local/bin: no WARN line" "" "$(warn_lines)"
SQLFMT_V="" doctor "$H0"
assert_eq "10.7 --version fails: exit code 0" 0 "$RC"
assert_eq "10.8 --version fails: the one WARN line" "WARN sqlfmt ($TMPD/bin/sqlfmt does not run): $FIX_SQLFMT" "$(warn_lines)"
SQLFMT_V="usage: sqlfmt [OPTIONS]" doctor "$H0"
assert_eq "10.9 other text: the one WARN line" "WARN sqlfmt ($TMPD/bin/sqlfmt does not run): $FIX_SQLFMT" "$(warn_lines)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
