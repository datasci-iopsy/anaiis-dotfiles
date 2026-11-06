#!/usr/bin/env bash
# tests/e2e-git-identity.sh -- does the settings env block override the git identity in a real Claude Code session?
#
# Why this matters: an env value in settings.json reaches every command of the Bash tool, and git reads
# GIT_AUTHOR_* and GIT_COMMITTER_* before any git config. The dotfiles once set the identity there, so no
# machine and no repo could use its own. Now the dotfiles set no identity, and each machine sets it in its
# git config (README, step 6). tests/test-rules-integrity.sh (section 7) checks the file. This suite checks
# what a live session does with it.
#
# Method: each case starts `claude -p` in a temp git repo whose local config sets a test noreply address,
# with only generated settings loaded (--setting-sources project --settings <generated>), as
# tests/e2e-nested-session.sh does. The Bash tool runs `git var GIT_AUTHOR_IDENT`. The suite reads the tool
# result from stream-json. It never trusts the model's own summary. Each session starts without the four
# GIT_AUTHOR_* and GIT_COMMITTER_* variables: a parent Claude Code session can export them, and an inherited
# value would decide the result.
#
# Cases:
#   settings   the env block of the settings under test. The tool result must show the local address.
#   control    the same env block plus GIT_AUTHOR_EMAIL set to a marker address, the shape of the old
#              settings. The tool result must show the marker, so the first case can detect the defect.
#
# Opt-in, because every case spends tokens (two short sessions on the haiku model):
#   E2E=1 bash tests/e2e-git-identity.sh
# Env overrides:
#   SETTINGS   settings.json under test (default: claude/settings.json of this repo). Pass a file that
#              sets the identity in its env block to check that the first case fails.
#   E2E_MODEL  model for the sessions (default: haiku)
#
# Result per case: PASS, FAIL, or NOT RUN. NOT RUN means claude could not run or the model did not run the
# command; it is never counted as a pass. WEAK means the control did not show the marker, so the first case
# does not detect an identity in the env block. The exit code is 1 on any FAIL, WEAK, or NOT RUN.

set -u

[ "${E2E:-}" = 1 ] || {
	echo "skip: set E2E=1 to run (spends tokens)"
	exit 0
}
for dep in claude jq git; do
	command -v "$dep" >/dev/null || {
		echo "skip: $dep not on PATH"
		exit 0
	}
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="${SETTINGS:-$REPO_DIR/claude/settings.json}"
MODEL="${E2E_MODEL:-haiku}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

LOCAL_EMAIL='999+e2e-local@users.noreply.github.com'
MARKER_EMAIL='998+e2e-env-marker@users.noreply.github.com'
TOOL_CMD='git var GIT_AUTHOR_IDENT'

PASS=0
FAIL=0
NOTRUN=0
WEAK=0

# start_case <tag> <extra env JSON>: run one session in the background, in a temp repo with a local identity.
start_case() {
	local d="$WORK/$1"
	mkdir -p "$d"
	git init -q --template= "$d/repo"
	git -C "$d/repo" config user.name e2e-local
	git -C "$d/repo" config user.email "$LOCAL_EMAIL"
	jq --argjson extra "$2" '{env: ((.env // {}) + $extra)}' "$SETTINGS" >"$d/settings.json"
	(cd "$d/repo" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
		claude -p --setting-sources project --settings "$d/settings.json" --model "$MODEL" \
		--no-session-persistence --allowedTools "Bash" --output-format stream-json --verbose \
		"Use the Bash tool to run exactly this command and nothing else: $TOOL_CMD   Then reply done." \
		>"$d/stream.jsonl" 2>"$d/stderr.txt") &
}

finished_ok() { jq -e 'select(.type == "result" and (.is_error | not))' "$WORK/$1/stream.jsonl" >/dev/null 2>&1; }

# tool_line <tag>: the result of the first Bash call whose command holds TOOL_CMD.
tool_line() {
	jq -rs --arg k "$TOOL_CMD" '
		[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
			| select((.input.command // "") | contains($k)) | .id] as $ids
		| [.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
			| select(.tool_use_id as $i | $ids | index($i)) | .content | tostring] | first // empty' \
		"$WORK/$1/stream.jsonl" 2>/dev/null
}

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

# eval_case <tag> <name> <wanted email> <label when the result lacks it: FAIL|WEAK>
eval_case() {
	local line
	finished_ok "$1" || {
		verdict "$2" NOTRUN "claude did not finish ($(head -c 120 "$WORK/$1/stderr.txt" 2>/dev/null))"
		return
	}
	line="$(tool_line "$1")"
	[ -n "$line" ] || {
		verdict "$2" NOTRUN "no Bash tool result for $TOOL_CMD"
		return
	}
	if printf '%s\n' "$line" | grep -qF "<$3>"; then
		verdict "$2" PASS "$line"
	else
		verdict "$2" "$4" "$line (wanted <$3>)"
	fi
}

echo "settings under test: $SETTINGS"
echo "local address: $LOCAL_EMAIL; marker address: $MARKER_EMAIL; model: $MODEL"

start_case settings '{}'
start_case control "$(jq -n --arg m "$MARKER_EMAIL" '{GIT_AUTHOR_EMAIL: $m}')"
wait

eval_case settings "the settings under test leave the local git identity in place" "$LOCAL_EMAIL" FAIL
eval_case control "control: an env block identity overrides the local git identity" "$MARKER_EMAIL" WEAK

printf '\ne2e-git-identity: %s passed, %s failed, %s weak, %s not run\n' "$PASS" "$FAIL" "$WEAK" "$NOTRUN"
[ "$FAIL" -eq 0 ] && [ "$WEAK" -eq 0 ] && [ "$NOTRUN" -eq 0 ]
