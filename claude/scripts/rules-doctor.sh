#!/usr/bin/env bash
# rules-doctor.sh — verify the behavioral rules pipeline end to end.
#
# Reports drift between the 4 lines in CLAUDE.md, rules/behavioral.md,
# the surface-behavioral-rules.sh hook, and its settings.json
# registration. Synthetically exercises the hook so problems surface
# without waiting for a real session.
#
# Exits 0 if all checks pass, 1 otherwise. Output is structured so the
# script is grep-able from a higher-level test harness.
#
# Checks:
#   A. CLAUDE.md contains all 4 lines verbatim.
#   B. The 4 lines appear before the `## Rules index` heading.
#   C. rules/behavioral.md exists with H1 + 4 H2 sections and is
#      referenced from CLAUDE.md's rules-index table.
#   D. surface-behavioral-rules.sh exists and is executable.
#   E. The hook is registered in settings.json UserPromptSubmit array.
#   F. Synthetic invocation: hook emits systemMessage containing all 4
#      lines on first call; emits nothing on second call.
#
# Usage: bash ~/.claude/scripts/rules-doctor.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_MD="$REPO_DIR/claude/CLAUDE.md"
BEHAV_MD="$REPO_DIR/claude/rules/behavioral.md"
HOOK="$REPO_DIR/claude/hooks/surface-behavioral-rules.sh"
SETTINGS="$REPO_DIR/claude/settings.json"

# Canonical 4 lines. Source of truth for drift detection.
LINES=(
	"Don't assume. Don't hide confusion. Surface tradeoffs."
	"Minimum code that solves the problem. Nothing speculative."
	"Touch only what you must. Clean up only your own mess."
	"Define success criteria. Loop until verified."
)

PASS=0
FAIL=0

ok() {
	printf '  PASS  %s\n' "$1"
	PASS=$((PASS + 1))
}
fail() {
	printf '  FAIL  %s\n        %s\n' "$1" "$2"
	FAIL=$((FAIL + 1))
}

# ── A. CLAUDE.md contains all 4 lines verbatim ────────────────────────────
echo "## A. CLAUDE.md verbatim content"
if [ -f "$CLAUDE_MD" ]; then
	ok "A.1 CLAUDE.md exists"
	for line in "${LINES[@]}"; do
		if grep -qF -- "$line" "$CLAUDE_MD"; then
			ok "A.2 CLAUDE.md contains: $line"
		else
			fail "A.2 CLAUDE.md missing line" "$line"
		fi
	done
else
	fail "A.1 CLAUDE.md exists" "missing: $CLAUDE_MD"
fi

# ── B. Ordering: 4 lines appear before Rules index ────────────────────────
echo "## B. Ordering"
if [ -f "$CLAUDE_MD" ]; then
	BEHAV_LN=$(grep -n '^## Behavioral rules' "$CLAUDE_MD" | head -1 | cut -d: -f1)
	INDEX_LN=$(grep -n '^## Rules index' "$CLAUDE_MD" | head -1 | cut -d: -f1)
	if [ -n "$BEHAV_LN" ] && [ -n "$INDEX_LN" ] && [ "$BEHAV_LN" -lt "$INDEX_LN" ]; then
		ok "B.1 Behavioral rules section precedes Rules index ($BEHAV_LN < $INDEX_LN)"
	else
		fail "B.1 ordering" "behavioral=$BEHAV_LN, index=$INDEX_LN"
	fi
fi

# ── C. behavioral.md structure and cross-reference ────────────────────────
echo "## C. rules/behavioral.md"
if [ -f "$BEHAV_MD" ]; then
	ok "C.1 rules/behavioral.md exists"
	if head -1 "$BEHAV_MD" | grep -qE '^# '; then
		ok "C.2 has H1 title"
	else
		fail "C.2 H1 title" "first line is not '# Title'"
	fi
	H2_CT=$(grep -cE '^## [1-4]\.' "$BEHAV_MD" || true)
	if [ "${H2_CT:-0}" -eq 4 ]; then
		ok "C.3 has 4 numbered H2 sections"
	else
		fail "C.3 H2 sections" "expected 4, found $H2_CT"
	fi
	if grep -qF 'rules/behavioral.md' "$CLAUDE_MD"; then
		ok "C.4 referenced from CLAUDE.md rules-index"
	else
		fail "C.4 cross-reference" "rules/behavioral.md not mentioned in CLAUDE.md"
	fi
else
	fail "C.1 rules/behavioral.md" "missing: $BEHAV_MD"
fi

# ── D. Hook file present and executable ───────────────────────────────────
echo "## D. surface-behavioral-rules.sh"
if [ -f "$HOOK" ]; then
	ok "D.1 hook file exists"
	if [ -x "$HOOK" ]; then
		ok "D.2 hook is executable"
	else
		fail "D.2 executable bit" "chmod +x $HOOK"
	fi
else
	fail "D.1 hook file" "missing: $HOOK"
fi

# ── E. Hook registered in settings.json ───────────────────────────────────
echo "## E. settings.json registration"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
	REGISTERED=$(jq -r '.hooks.UserPromptSubmit[].hooks[].command' "$SETTINGS" \
		| grep -c 'surface-behavioral-rules.sh' || true)
	if [ "${REGISTERED:-0}" -ge 1 ]; then
		ok "E.1 hook registered in UserPromptSubmit"
	else
		fail "E.1 registration" "surface-behavioral-rules.sh not in settings.json"
	fi
	# Order check: should be first so behavioral rules load before others.
	FIRST_CMD=$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$SETTINGS")
	if printf '%s' "$FIRST_CMD" | grep -q 'surface-behavioral-rules.sh'; then
		ok "E.2 hook is first in UserPromptSubmit chain"
	else
		fail "E.2 hook ordering" "first hook is: $FIRST_CMD"
	fi
else
	fail "E.* prerequisites" "jq missing or settings.json absent"
fi

# ── F. Synthetic hook invocation ──────────────────────────────────────────
echo "## F. Hook synthetic invocation"
if [ -x "$HOOK" ] && command -v jq >/dev/null 2>&1; then
	TEST_SID="doctor-$$-$RANDOM"
	MARKER="/tmp/claude-session-${TEST_SID}.behavioral-loaded"
	rm -f "$MARKER"
	INPUT_F=$(jq -n --arg sid "$TEST_SID" \
		'{"session_id":$sid,"hook_event_name":"UserPromptSubmit","prompt":"x"}')
	OUT1=$(printf '%s' "$INPUT_F" | bash "$HOOK" 2>/dev/null || true)
	OUT2=$(printf '%s' "$INPUT_F" | bash "$HOOK" 2>/dev/null || true)
	rm -f "$MARKER"

	if printf '%s' "$OUT1" | jq -e '.systemMessage' >/dev/null 2>&1; then
		ok "F.1 first invocation emits systemMessage JSON"
		MSG=$(printf '%s' "$OUT1" | jq -r '.systemMessage')
		MISSING=0
		for line in "${LINES[@]}"; do
			if ! printf '%s' "$MSG" | grep -qF -- "$line"; then
				MISSING=$((MISSING + 1))
				fail "F.2 systemMessage line" "missing: $line"
			fi
		done
		if [ "$MISSING" -eq 0 ]; then
			ok "F.2 systemMessage contains all 4 lines verbatim"
		fi
	else
		fail "F.1 first invocation" "no valid systemMessage JSON; got: $(printf '%s' "$OUT1" | head -c 80)"
	fi

	if [ -z "$OUT2" ]; then
		ok "F.3 second invocation in same session emits nothing"
	else
		fail "F.3 second invocation" "expected empty, got: $(printf '%s' "$OUT2" | head -c 80)"
	fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "rules-doctor: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
