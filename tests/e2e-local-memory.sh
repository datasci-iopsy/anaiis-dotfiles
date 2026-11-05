#!/usr/bin/env bash
# tests/e2e-local-memory.sh -- does a real Claude Code session load global memory from a local folder?
#
# Why this matters: install.sh keeps ~/.claude/memory as a real folder, not a link into the repo. The
# SessionStart hook claude/hooks/session-start-context.sh reads ~/.claude/memory/MEMORY.md from that
# folder and sends it to the model as additionalContext. This suite checks that path in a live session.
#
# Method: each case starts `claude -p` in a temp directory with only generated settings loaded
# (--setting-sources project --settings <generated>), as tests/e2e-nested-session.sh does. The claude
# process keeps the real HOME, because it needs the real login. Only the hook gets a throwaway HOME,
# built by tests/lib/fresh-home.sh: the hook command is `HOME=<throwaway> bash <repo>/claude/hooks/...`.
#
# Evidence: the stream-json event of type system, subtype hook_response, for SessionStart. Its stdout
# field holds the JSON that the hook printed, so the suite reads additionalContext from it. The prompt
# also asks the model for the canary line, and the reply proves that the payload reached the model.
# A random canary cannot be guessed.
#
# Cases:
#   real folder   ~/.claude/memory is a real folder (not a link) whose MEMORY.md holds a random canary.
#                 The hook payload and the reply must show the canary.
#   control       ~/.claude/memory is absent. The hook payload must hold no canary and the reply must
#                 be NONE. This proves that the first case can fail.
#
# Opt-in, because every case spends tokens (two short sessions on the haiku model):
#   E2E=1 bash tests/e2e-local-memory.sh
# Env overrides:
#   E2E_MODEL  model for the sessions (default: haiku)
#
# Result per case: PASS, FAIL, or NOT RUN. NOT RUN means claude could not run or the hook did not run;
# it is never counted as a pass. WEAK means the control showed a canary or no NONE reply, so the first
# case does not prove that the folder is the source. The exit code is 1 on any FAIL, WEAK, or NOT RUN.

set -u

[ "${E2E:-}" = 1 ] || {
	echo "skip: set E2E=1 to run (spends tokens)"
	exit 0
}
for dep in claude jq openssl; do
	command -v "$dep" >/dev/null || {
		echo "skip: $dep not on PATH"
		exit 0
	}
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${E2E_MODEL:-haiku}"
PROMPT="Reply with only the line from your context that starts with CANARY-, or NONE."
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/fresh-home.sh
. "$REPO_DIR/tests/lib/fresh-home.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
NOTRUN=0
WEAK=0
STREAM=""

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

# run_claude <tag> <throwaway home>: sets STREAM. Fails when the session did not finish cleanly.
run_claude() {
	local d="$WORK/$1"
	mkdir -p "$d/cwd"
	STREAM="$d/stream.jsonl"
	jq -n --arg h "$2" --arg hook "$REPO_DIR/claude/hooks/session-start-context.sh" \
		'{hooks: {SessionStart: [{hooks: [{type: "command", command: "HOME=\($h | @sh) bash \($hook | @sh)"}]}]}}' \
		>"$d/settings.json"
	(cd "$d/cwd" && claude -p --setting-sources project --settings "$d/settings.json" --model "$MODEL" \
		--no-session-persistence --output-format stream-json --verbose --include-hook-events "$PROMPT" \
		>"$STREAM" 2>"$d/stderr.txt")
	jq -e 'select(.type == "result" and (.is_error | not))' "$STREAM" >/dev/null 2>&1
}

# hook_ran: the SessionStart hook ran and exited 0.
hook_ran() {
	jq -e 'select(.type == "system" and .subtype == "hook_response" and .hook_event == "SessionStart" and .exit_code == 0)' \
		"$STREAM" >/dev/null 2>&1
}

# hook_context: the additionalContext that the SessionStart hook printed, or nothing.
hook_context() {
	jq -rs '[.[] | select(.type == "system" and .subtype == "hook_response" and .hook_event == "SessionStart")
		| .stdout | fromjson? | .hookSpecificOutput.additionalContext // empty][0] // empty' "$STREAM"
}

reply() { jq -r 'select(.type == "result") | .result' "$STREAM" | tr -d '\n'; }

echo "model: $MODEL"

echo "== real folder"
NAME="a real ~/.claude/memory folder reaches the session"
H_REAL="$(TMPDIR="$WORK" fresh_home_new "$REPO_DIR")" || exit 1
CANARY="CANARY-$(openssl rand -hex 8)"
# Check the folder before the write: a link could send the canary into the repo.
if ! [ -d "$H_REAL/.claude/memory" ] || [ -L "$H_REAL/.claude/memory" ]; then
	verdict "$NAME" FAIL "fresh_home_new did not build ~/.claude/memory as a real folder"
elif ! printf '%s\n' "$CANARY" >>"$H_REAL/.claude/memory/MEMORY.md"; then
	verdict "$NAME" NOTRUN "could not write the canary"
elif ! run_claude real "$H_REAL"; then
	verdict "$NAME" NOTRUN "claude did not finish ($(head -c 120 "$WORK/real/stderr.txt"))"
elif ! hook_ran; then
	verdict "$NAME" NOTRUN "no SessionStart hook_response with exit code 0"
elif ! hook_context | grep -qF "$CANARY"; then
	verdict "$NAME" FAIL "the hook payload does not hold $CANARY"
elif ! reply | grep -qF "$CANARY"; then
	verdict "$NAME" FAIL "the hook payload holds $CANARY, but the reply is: $(reply | head -c 120)"
else
	verdict "$NAME" PASS "hook payload and reply hold $CANARY"
fi

echo "== control"
NAME="an absent ~/.claude/memory folder gives no canary"
H_CTL="$(TMPDIR="$WORK" fresh_home_new "$REPO_DIR")" || exit 1
rm -rf "$H_CTL/.claude/memory"
if [ -e "$H_CTL/.claude/memory" ]; then
	verdict "$NAME" NOTRUN "could not remove the memory folder of the control home"
elif ! run_claude control "$H_CTL"; then
	verdict "$NAME" NOTRUN "claude did not finish ($(head -c 120 "$WORK/control/stderr.txt"))"
elif ! hook_ran; then
	verdict "$NAME" NOTRUN "no SessionStart hook_response with exit code 0"
elif hook_context | grep -qF "CANARY-"; then
	verdict "$NAME" WEAK "the control hook payload holds a canary"
elif reply | grep -qF "CANARY-" || ! reply | grep -qF "NONE"; then
	verdict "$NAME" WEAK "the control reply is not NONE: $(reply | head -c 120)"
else
	verdict "$NAME" PASS "no canary in the hook payload, reply: $(reply)"
fi

printf '\ne2e-local-memory: %s passed, %s failed, %s weak, %s not run\n' "$PASS" "$FAIL" "$WEAK" "$NOTRUN"
[ "$FAIL" -eq 0 ] && [ "$WEAK" -eq 0 ] && [ "$NOTRUN" -eq 0 ]
