#!/usr/bin/env bash
# tests/test-em-dash-guard.sh, verify the block-em-dash PreToolUse
# hook denies Edit/Write/MultiEdit/NotebookEdit payloads containing
# U+2014 and allows clean payloads. Also verifies registration in
# settings.json.
#
# Exits 0 on full pass; non-zero on first failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/block-em-dash.sh"
SETTINGS="$REPO_DIR/claude/settings.json"
EM=$'\xe2\x80\x94'

PASS=0
FAIL=0

assert_exit() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected exit=%s, got %s\n' \
			"$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

assert_contains() {
	local name="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected to contain: %s\n        actual:   %s\n' \
			"$name" "$needle" "$haystack"
		FAIL=$((FAIL + 1))
	fi
}

run_hook() {
	# Run hook with given JSON, return exit code; capture stderr to /tmp.
	local json="$1"
	printf '%s' "$json" | bash "$HOOK" 2>/tmp/em-dash.stderr
	echo $?
}

# ── 1. Hook file present and executable ───────────────────────────────────
echo "# 1. Hook file"
[ -f "$HOOK" ] && PASS=$((PASS + 1)) && echo "  PASS  1.1 hook exists" \
	|| { FAIL=$((FAIL + 1)); echo "  FAIL  1.1 hook missing: $HOOK"; }
[ -x "$HOOK" ] && PASS=$((PASS + 1)) && echo "  PASS  1.2 hook executable" \
	|| { FAIL=$((FAIL + 1)); echo "  FAIL  1.2 hook not executable"; }

# ── 2. Registered in settings.json under PreToolUse ───────────────────────
echo "# 2. settings.json registration"
if command -v jq >/dev/null 2>&1; then
	REG=$(jq -r '[.hooks.PreToolUse[]
		| select(.matcher | test("Write|Edit|MultiEdit|NotebookEdit"))
		| .hooks[].command] | join("|")' "$SETTINGS")
	assert_contains "2.1 hook registered for Edit-family matcher" \
		"block-em-dash.sh" "$REG"
	MATCHER=$(jq -r '[.hooks.PreToolUse[]
		| select(.hooks[].command | contains("block-em-dash.sh"))
		| .matcher] | first' "$SETTINGS")
	for tool in Write Edit MultiEdit NotebookEdit; do
		case "$MATCHER" in
			*"$tool"*) echo "  PASS  2.2 matcher covers $tool"; PASS=$((PASS + 1)) ;;
			*) echo "  FAIL  2.2 matcher missing $tool: $MATCHER"; FAIL=$((FAIL + 1)) ;;
		esac
	done
else
	echo "  SKIP  jq missing"
fi

# ── 3. Deny: Write with em-dash in content ────────────────────────────────
echo "# 3. Deny Write with em dash"
INPUT=$(jq -n --arg em "$EM" \
	'{tool_name:"Write",tool_input:{file_path:"/tmp/x.md",content:("hi "+$em+" bye")}}')
RC=$(run_hook "$INPUT")
assert_exit "3.1 Write em-dash denied (exit 2)" "2" "$RC"
assert_contains "3.2 stderr explains the block" "BLOCKED" "$(cat /tmp/em-dash.stderr)"
assert_contains "3.3 stderr names the file path" "/tmp/x.md" "$(cat /tmp/em-dash.stderr)"

# ── 4. Allow: Write with clean content ────────────────────────────────────
echo "# 4. Allow clean Write"
INPUT=$(jq -n '{tool_name:"Write",tool_input:{file_path:"/tmp/x.md",content:"hi, bye"}}')
RC=$(run_hook "$INPUT")
assert_exit "4.1 clean Write allowed (exit 0)" "0" "$RC"

# ── 5. Deny: Edit with em-dash in new_string ──────────────────────────────
echo "# 5. Deny Edit with em dash"
INPUT=$(jq -n --arg em "$EM" \
	'{tool_name:"Edit",tool_input:{file_path:"/tmp/x.md",old_string:"a",new_string:("b "+$em+" c")}}')
RC=$(run_hook "$INPUT")
assert_exit "5.1 Edit em-dash denied (exit 2)" "2" "$RC"

# ── 6. Allow: Edit with clean new_string ──────────────────────────────────
echo "# 6. Allow clean Edit"
INPUT=$(jq -n '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.md",old_string:"a",new_string:"b, c"}}')
RC=$(run_hook "$INPUT")
assert_exit "6.1 clean Edit allowed (exit 0)" "0" "$RC"

# ── 7. Deny: MultiEdit with em-dash in any new_string ─────────────────────
echo "# 7. Deny MultiEdit with em dash"
INPUT=$(jq -n --arg em "$EM" \
	'{tool_name:"MultiEdit",tool_input:{file_path:"/tmp/x.md",
		edits:[{old_string:"a",new_string:"b"},
		       {old_string:"c",new_string:("d "+$em+" e")}]}}')
RC=$(run_hook "$INPUT")
assert_exit "7.1 MultiEdit em-dash denied (exit 2)" "2" "$RC"

# ── 8. Allow: MultiEdit with all clean edits ──────────────────────────────
echo "# 8. Allow clean MultiEdit"
INPUT=$(jq -n '{tool_name:"MultiEdit",tool_input:{file_path:"/tmp/x.md",
	edits:[{old_string:"a",new_string:"b"},{old_string:"c",new_string:"d"}]}}')
RC=$(run_hook "$INPUT")
assert_exit "8.1 clean MultiEdit allowed (exit 0)" "0" "$RC"

# ── 9. Deny: NotebookEdit with em-dash in new_source ──────────────────────
echo "# 9. Deny NotebookEdit with em dash"
INPUT=$(jq -n --arg em "$EM" \
	'{tool_name:"NotebookEdit",tool_input:{notebook_path:"/tmp/x.ipynb",new_source:("# "+$em+"")}}')
RC=$(run_hook "$INPUT")
assert_exit "9.1 NotebookEdit em-dash denied (exit 2)" "2" "$RC"

# ── 10. Pass-through: unrelated tool (Bash) ───────────────────────────────
echo "# 10. Pass-through unrelated tools"
INPUT=$(jq -n --arg em "$EM" \
	'{tool_name:"Bash",tool_input:{command:("echo "+$em)}}')
RC=$(run_hook "$INPUT")
assert_exit "10.1 Bash with em dash in command is not the hook's job" "0" "$RC"

# ── 11. The hook itself contains no em dash (self-consistency) ────────────
echo "# 11. Hook self-consistency"
if grep -qF -- "$EM" "$HOOK"; then
	echo "  FAIL  11.1 hook source contains an em dash"
	FAIL=$((FAIL + 1))
else
	echo "  PASS  11.1 hook source is em-dash-free"
	PASS=$((PASS + 1))
fi

rm -f /tmp/em-dash.stderr

echo
echo "──────────────────────────────────────────────"
echo "test-em-dash-guard: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
