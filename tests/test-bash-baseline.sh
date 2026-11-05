#!/usr/bin/env bash
# tests/test-bash-baseline.sh -- the harness runs on one approved Homebrew bash major.
#
# Why this matters: Claude Code picks the shell of the Bash tool from $SHELL, and VS Code hands it a
# stale /bin/bash (bash 3.2). With no $SHELL at all it picks zsh. A hook command of the form
# `bash script` follows PATH, so a PATH without Homebrew runs every hook on bash 3.2. The pin
# env.CLAUDE_CODE_SHELL in settings.json, and a command prefix that uses it, close both gaps. This suite
# fails when the pin or the prefix is lost, when the bash on PATH is not an approved major (bash 4 fails;
# a bash 6 fails until someone approves it), or when a script names /bin/bash in its shebang.
#
# The approved majors are the one line APPROVED_BASH_MAJORS in claude/scripts/bootstrap-doctor.sh.
# The suite asks the doctor about the repo settings.json, so the version logic exists once. Fail-to-fail
# cases then break copies of the settings (a bash 4 pin, a bash 6 pin, a bare command) and expect the
# doctor to report each one.
#
# Env override, used to check another settings file:
#   SETTINGS   path of the settings.json under test (default: claude/settings.json of this repo)
#
# Usage: bash tests/test-bash-baseline.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="${SETTINGS:-$REPO_DIR/claude/settings.json}"
DOCTOR="$REPO_DIR/claude/scripts/bootstrap-doctor.sh"

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

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/test-bash-baseline.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

APPROVED="$(sed -n 's/^APPROVED_BASH_MAJORS="\(.*\)"$/\1/p' "$DOCTOR")"
LOW=""
HIGH=""
for m in $APPROVED; do
	[ -n "$LOW" ] || LOW=$((m - 1))
	HIGH=$((m + 1))
done

# is_approved <major>: succeed when the major is in the approved list.
is_approved() {
	local m
	for m in $APPROVED; do
		[ "$1" = "$m" ] && return 0
	done
	return 1
}

# major_of <bash>: print the major version of the given bash binary.
major_of() {
	# shellcheck disable=SC2016 # the given bash expands ${BASH_VERSINFO[0]}, not this shell
	"$1" -c 'printf %s "${BASH_VERSINFO[0]}"' 2>/dev/null
}

# doctor_on <settings.json>: run the doctor in a throwaway HOME that holds a copy of the file. The
# output keeps only the lines of check 7. The other checks report the empty HOME, which is not the subject.
doctor_on() {
	local h
	h="$(mktemp -d "$TMPD/home.XXXXXX")"
	mkdir -p "$h/.claude"
	cp "$1" "$h/.claude/settings.json"
	HOME="$h" "$BASH" "$DOCTOR" 2>&1 | grep -E '^(ok|MISSING) (harness bash|hook commands)' || true
}

# stub_bash <major>: print the path of a stub that answers -c with the given major.
stub_bash() {
	local p="$TMPD/stub-bash-$1"
	# shellcheck disable=SC2016 # $1 stays literal: it is the text of the stub script
	printf '#!/bin/sh\n[ "$1" = "-c" ] || exit 64\nprintf %%s %s\n' "$1" >"$p"
	chmod +x "$p"
	printf '%s\n' "$p"
}

echo "--- 1. the approved list and the bash on PATH"
assert_eq "1.1 the doctor holds a non-empty approved list" yes "$([ -n "$APPROVED" ] && echo yes || echo no)"
PATH_BASH="$(command -v bash)"
PATH_MAJOR="$(major_of "$PATH_BASH")"
is_approved "$PATH_MAJOR" && PATH_OK=yes || PATH_OK=no
assert_eq "1.2 the bash on PATH ($PATH_BASH, major ${PATH_MAJOR:-unknown}) is approved (list: $APPROVED)" yes "$PATH_OK"

echo "--- 2. the repo settings.json"
assert_eq "2.1 the pin is the Homebrew bash path" "/opt/homebrew/bin/bash" "$(jq -r '.env.CLAUDE_CODE_SHELL // empty' "$SETTINGS")"
REAL_OUT="$(doctor_on "$SETTINGS")"
assert_eq "2.2 the doctor accepts the pin" 1 "$(printf '%s\n' "$REAL_OUT" | grep -c '^ok harness bash ')"
assert_eq "2.3 the doctor accepts the command prefix" 1 "$(printf '%s\n' "$REAL_OUT" | grep -c '^ok hook commands start with the pin prefix ')"
assert_eq "2.4 the doctor reports no gap for check 7" 0 "$(printf '%s\n' "$REAL_OUT" | grep -c '^MISSING ')"
TOTAL="$(jq '[.. | objects | select(has("command")) | .command | strings] | length' "$SETTINGS")"
assert_eq "2.5 the file holds commands to check (the check is not vacuous)" yes "$([ "$TOTAL" -gt 0 ] && echo yes || echo no)"

echo "--- 3. no script names /bin/bash in its shebang"
SHEBANG_FILES="$(git -C "$REPO_DIR" ls-files -- claude/hooks claude/scripts bin bash)"
SHEBANG_BAD=""
SHEBANG_N=0
while IFS= read -r f; do
	[ -f "$REPO_DIR/$f" ] || continue
	SHEBANG_N=$((SHEBANG_N + 1))
	head -n 1 "$REPO_DIR/$f" | grep -qE '^#![[:space:]]*/bin/bash' && SHEBANG_BAD="$SHEBANG_BAD $f"
done <<EOF
$SHEBANG_FILES
EOF
assert_eq "3.1 the tracked scripts are found (the check is not vacuous)" yes "$([ "$SHEBANG_N" -gt 0 ] && echo yes || echo no)"
assert_eq "3.2 no shebang names /bin/bash (use #!/usr/bin/env bash)" "" "$SHEBANG_BAD"

echo "--- 4. fail-to-fail: broken copies of the settings are reported"
jq --arg p "$(stub_bash "$LOW")" '.env.CLAUDE_CODE_SHELL = $p' "$SETTINGS" >"$TMPD/pin-low.json"
assert_eq "4.1 a pin to a bash $LOW is reported (approved: $APPROVED)" 1 \
	"$(doctor_on "$TMPD/pin-low.json" | grep -c "^MISSING harness bash .* (major $LOW, approved: $APPROVED)")"
jq --arg p "$(stub_bash "$HIGH")" '.env.CLAUDE_CODE_SHELL = $p' "$SETTINGS" >"$TMPD/pin-high.json"
assert_eq "4.2 a pin to a bash $HIGH is reported (approved: $APPROVED)" 1 \
	"$(doctor_on "$TMPD/pin-high.json" | grep -c "^MISSING harness bash .* (major $HIGH, approved: $APPROVED)")"
APPROVED_FIRST="${APPROVED%% *}"
jq --arg p "$(stub_bash "$APPROVED_FIRST")" '.env.CLAUDE_CODE_SHELL = $p' "$SETTINGS" >"$TMPD/pin-ok.json"
assert_eq "4.3 a pin to a bash $APPROVED_FIRST passes" 1 "$(doctor_on "$TMPD/pin-ok.json" | grep -c '^ok harness bash ')"
jq 'del(.env.CLAUDE_CODE_SHELL)' "$SETTINGS" >"$TMPD/no-pin.json"
assert_eq "4.4 a lost pin is reported" 1 "$(doctor_on "$TMPD/no-pin.json" | grep -c '^MISSING harness bash pin ')"
jq '.hooks.Stop[0].hooks[0].command |= sub("^\\$\\{CLAUDE_CODE_SHELL:-bash\\} "; "bash ")' "$SETTINGS" >"$TMPD/bare.json"
assert_eq "4.5 one command with a bare bash is reported" 1 \
	"$(doctor_on "$TMPD/bare.json" | grep -c "^MISSING hook commands without the pin prefix (1 of $TOTAL)")"
# Case 1.2 applies is_approved to the major of the bash that PATH finds first. The same rule must reject
# a bash below the approved list and a bash above it.
VERDICTS=""
for major in "$LOW" "$HIGH"; do
	if is_approved "$(major_of "$(stub_bash "$major")")"; then VERDICTS="$VERDICTS approved"; else VERDICTS="$VERDICTS rejected"; fi
done
assert_eq "4.6 the rule of case 1.2 rejects a bash $LOW and a bash $HIGH" " rejected rejected" "$VERDICTS"

echo "--- 5. every PreToolUse guard blocks when it cannot start"
TOTAL_PRETOOL="$(jq '[.hooks.PreToolUse[].hooks[]] | length' "$SETTINGS")"
BLOCKED_PRETOOL="$(jq '[.hooks.PreToolUse[].hooks[] | select(.onFailure == "block")] | length' "$SETTINGS")"
assert_eq "5.1 a guard that cannot start must block, not pass: every PreToolUse hook sets onFailure to block ($BLOCKED_PRETOOL of $TOTAL_PRETOOL)" \
	"$TOTAL_PRETOOL" "$BLOCKED_PRETOOL"

echo "--- 6. a harness hook starts its child scripts with the running bash"
# Why: the pin reaches the entry point of a hook only. A child that starts with a bare bash resolves
# through PATH, which holds /bin/bash 3.2 in a GUI launch. The shims repo-*.sh run under git, not under
# the harness, so the pin does not reach them (decision D-015); the filter leaves them out.
BARE_CHILDREN="$(grep -n 'bash "\$' "$REPO_DIR"/claude/hooks/*.sh | grep -v -e '/repo-[a-z-]*\.sh:' || true)"
assert_eq "6.1 no harness hook starts a child script with a bare bash" "" "$BARE_CHILDREN"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
