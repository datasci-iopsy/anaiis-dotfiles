#!/usr/bin/env bash
# tests/e2e-bash-shell.sh -- which bash runs the Bash tool and the hooks in real Claude Code sessions?
#
# Why this matters: Claude Code picks the shell of the Bash tool from $SHELL. VS Code hands it a stale
# /bin/bash (bash 3.2). With no $SHELL it picks zsh. A hook command of the form `bash script` follows
# PATH, so a PATH without Homebrew runs the hook on bash 3.2. The pin env.CLAUDE_CODE_SHELL in
# settings.json, and the command prefix ${CLAUDE_CODE_SHELL:-bash}, are meant to close all of that.
# tests/test-bash-baseline.sh checks the files. This suite checks what a live session does with them.
#
# Method: each case starts `claude -p` in a temp directory with only generated settings loaded
# (--setting-sources project --settings <generated>), as tests/e2e-nested-session.sh does. The generated
# settings hold the pin and the command prefix taken from the repo settings.json. The Bash tool prints its
# own bash major, and a PreToolUse hook that uses the repo prefix records the major of its interpreter.
# The suite reads the tool result from stream-json and the hook record from a file. It never trusts the
# model's own summary.
#
# Launch environments (the three that an editor or terminal creates):
#   terminal    stale SHELL=/bin/bash, PATH as in the shell that runs this suite
#   gui-stale   stale SHELL=/bin/bash, PATH without Homebrew (a GUI app that starts claude)
#   gui-nosh    no SHELL variable, PATH without Homebrew
# Each environment runs twice. The pinned run must show an approved major for the Bash tool and for the
# hook. The control run drops the pin and must show an unapproved major, so the case detects the defect.
# One more case sets the same variable in the shell and in the settings env block: the settings value
# must win. That fact is the reason behind the configuration homes policy in rules/environment.md.
#
# Opt-in, because every case spends tokens (seven short sessions on the haiku model):
#   E2E=1 bash tests/e2e-bash-shell.sh
# Env overrides:
#   SETTINGS   settings.json under test (default: claude/settings.json of this repo). Pass the file from
#              main, which has no pin, to check that the pinned cases fail without one.
#   E2E_MODEL  model for the sessions (default: haiku)
#
# Result per case: PASS, FAIL, or NOT RUN. NOT RUN means claude could not run or the model did not make
# the expected tool call; it is never counted as a pass. WEAK means a control run also showed an approved
# major, so the case does not detect a lost pin. The exit code is 1 on any FAIL, WEAK, or NOT RUN.

set -u

[ "${E2E:-}" = 1 ] || {
	echo "skip: set E2E=1 to run (spends tokens)"
	exit 0
}
for dep in claude jq; do
	command -v "$dep" >/dev/null || {
		echo "skip: $dep not on PATH"
		exit 0
	}
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="${SETTINGS:-$REPO_DIR/claude/settings.json}"
DOCTOR="$REPO_DIR/claude/scripts/bootstrap-doctor.sh"
MODEL="${E2E_MODEL:-haiku}"
CLAUDE="$(command -v claude)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APPROVED="$(sed -n 's/^APPROVED_BASH_MAJORS="\(.*\)"$/\1/p' "$DOCTOR")"
# The pin and the command prefix come from the settings under test. A file without them yields an empty
# pin and the prefix `bash`, so the pinned cases then show the defect and fail, as they must.
PIN="$(jq -r '.env.CLAUDE_CODE_SHELL // empty' "$SETTINGS")"
PREFIX="$(jq -r '[.. | objects | select(has("command")) | .command | strings][0] | split(" ")[0]' "$SETTINGS")"
# shellcheck disable=SC2016 # ${...} stays literal: it is the text that settings.json holds
WANT_PREFIX='${CLAUDE_CODE_SHELL:-bash}'
# shellcheck disable=SC2016 # the Bash tool expands these variables, not this shell
TOOL_CMD='echo "tool-major=${BASH_VERSINFO[0]:-none} zsh=${ZSH_VERSION:-none} PROBE_X=${PROBE_X:-unset}"'

PASS=0
FAIL=0
NOTRUN=0
WEAK=0

is_approved() {
	local m
	for m in $APPROVED; do
		[ "$1" = "$m" ] && return 0
	done
	return 1
}

# The hook script is run by whatever interpreter the repo prefix selects. It records that interpreter.
cat >"$WORK/interp.sh" <<'EOF'
echo "$1 hook-major=${BASH_VERSINFO[0]:-none}" >>"$2"
EOF

GUI_PATH=/usr/bin:/bin:/usr/sbin:/sbin
ME="${USER:-$(id -un)}"
GUI_BASE=(env -i HOME="$HOME" USER="$ME" LOGNAME="$ME" TMPDIR="${TMPDIR:-/tmp}")

# start_case <tag> <pin yes|no> <extra env JSON> <env words...>: run one session in the background.
start_case() {
	local tag="$1" usepin="$2" extra="$3" d
	shift 3
	d="$WORK/$tag"
	mkdir -p "$d"
	jq -n --arg hook "$PREFIX $WORK/interp.sh $tag $WORK/hook.log" --arg pin "$PIN" --arg usepin "$usepin" --argjson extra "$extra" '
		{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $hook}]}]}}
		+ {env: ((if $usepin == "yes" then {CLAUDE_CODE_SHELL: $pin} else {} end) + $extra)}' >"$d/settings.json"
	(cd "$d" && "$@" "$CLAUDE" -p --setting-sources project --settings "$d/settings.json" --model "$MODEL" \
		--no-session-persistence --allowedTools "Bash" --output-format stream-json --verbose \
		"Use the Bash tool to run exactly this command and nothing else: $TOOL_CMD   Then reply done." \
		>"$d/stream.jsonl" 2>"$d/stderr.txt") &
}

finished_ok() { jq -e 'select(.type == "result" and (.is_error | not))' "$WORK/$1/stream.jsonl" >/dev/null 2>&1; }
tool_line() {
	jq -rs '[.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result") | .content | tostring] | first // empty' \
		"$WORK/$1/stream.jsonl" 2>/dev/null
}
tool_major() { tool_line "$1" | sed -n 's/.*tool-major=\([^ ]*\).*/\1/p'; }
hook_major() { sed -n "s/^$1 hook-major=//p" "$WORK/hook.log" 2>/dev/null | head -n 1; }

# verdict <name> <PASS|FAIL|NOTRUN|WEAK> <detail>
verdict() {
	local label="$2"
	[ "$label" = NOTRUN ] && label="NOT RUN"
	printf '  %s  %s: %s\n' "$label" "$1" "$3"
	case "$2" in
		PASS) PASS=$((PASS + 1)) ;;
		FAIL) FAIL=$((FAIL + 1)) ;;
		WEAK) WEAK=$((WEAK + 1)) ;;
		*) NOTRUN=$((NOTRUN + 1)) ;;
	esac
}

# eval_pinned <env label> <tag>: the pinned run must show approved majors for the tool and the hook.
eval_pinned() {
	local name="$1 with the pin" tm hm
	finished_ok "$2" || {
		verdict "$name" NOTRUN "claude did not finish ($(head -c 120 "$WORK/$2/stderr.txt" 2>/dev/null))"
		return
	}
	tm="$(tool_major "$2")"
	hm="$(hook_major "$2")"
	[ -n "$tm" ] || {
		verdict "$name" NOTRUN "no Bash tool result"
		return
	}
	[ -n "$hm" ] || {
		verdict "$name" NOTRUN "the hook did not run"
		return
	}
	if is_approved "$tm" && is_approved "$hm"; then
		verdict "$name" PASS "tool major $tm, hook major $hm"
	else
		verdict "$name" FAIL "tool major $tm, hook major $hm (approved: $APPROVED)"
	fi
}

# eval_control <env label> <tag> <check hook yes|no>: without the pin the tool major must not be approved.
eval_control() {
	local name="$1 without the pin" tm hm
	finished_ok "$2" || {
		verdict "$name" NOTRUN "claude did not finish ($(head -c 120 "$WORK/$2/stderr.txt" 2>/dev/null))"
		return
	}
	tm="$(tool_major "$2")"
	[ -n "$tm" ] || {
		verdict "$name" NOTRUN "no Bash tool result"
		return
	}
	if is_approved "$tm"; then
		verdict "$name" WEAK "the control shows an approved tool major $tm, so this case does not detect a lost pin"
		return
	fi
	if [ "$3" = yes ]; then
		hm="$(hook_major "$2")"
		if [ -z "$hm" ]; then
			verdict "$name" NOTRUN "the hook did not run"
			return
		elif is_approved "$hm"; then
			verdict "$name" WEAK "the control shows an approved hook major $hm"
			return
		fi
	fi
	verdict "$name" PASS "the control shows the defect: tool major $tm${hm:+, hook major $hm}"
}

echo "settings under test: $SETTINGS"
echo "pin: ${PIN:-(none)}; command prefix: $PREFIX; approved majors: $APPROVED; model: $MODEL"
if [ "$PREFIX" != "$WANT_PREFIX" ]; then
	verdict "the commands use the pin prefix" FAIL "the first command starts with $PREFIX, not $WANT_PREFIX"
fi

start_case terminal-pin yes '{}' env SHELL=/bin/bash
start_case terminal-ctl no '{}' env SHELL=/bin/bash
start_case gui-stale-pin yes '{}' "${GUI_BASE[@]}" SHELL=/bin/bash PATH="$GUI_PATH"
start_case gui-stale-ctl no '{}' "${GUI_BASE[@]}" SHELL=/bin/bash PATH="$GUI_PATH"
start_case gui-nosh-pin yes '{}' "${GUI_BASE[@]}" PATH="$GUI_PATH"
start_case gui-nosh-ctl no '{}' "${GUI_BASE[@]}" PATH="$GUI_PATH"
start_case precedence no '{"PROBE_X": "from-settings"}' env SHELL=/bin/bash PROBE_X=from-shell
wait

echo "== launch environments"
eval_pinned "terminal (stale SHELL, Homebrew PATH)" terminal-pin
eval_control "terminal (stale SHELL, Homebrew PATH)" terminal-ctl no
eval_pinned "gui-stale (stale SHELL, PATH without Homebrew)" gui-stale-pin
eval_control "gui-stale (stale SHELL, PATH without Homebrew)" gui-stale-ctl yes
eval_pinned "gui-nosh (no SHELL, PATH without Homebrew)" gui-nosh-pin
eval_control "gui-nosh (no SHELL, PATH without Homebrew)" gui-nosh-ctl yes

echo "== precedence"
PREC_NAME="a settings env value beats the same variable in the shell"
PREC_LINE="$(tool_line precedence)"
if ! finished_ok precedence || [ -z "$PREC_LINE" ]; then
	verdict "$PREC_NAME" NOTRUN "claude did not finish or ran no Bash tool"
elif printf '%s\n' "$PREC_LINE" | grep -q 'PROBE_X=from-settings'; then
	verdict "$PREC_NAME" PASS "$PREC_LINE"
else
	verdict "$PREC_NAME" FAIL "$PREC_LINE"
fi

printf '\ne2e-bash-shell: %s passed, %s failed, %s weak, %s not run\n' "$PASS" "$FAIL" "$WEAK" "$NOTRUN"
[ "$FAIL" -eq 0 ] && [ "$WEAK" -eq 0 ] && [ "$NOTRUN" -eq 0 ]
