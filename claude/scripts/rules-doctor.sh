#!/usr/bin/env bash
# rules-doctor.sh, verify the behavioral rules pipeline end to end.
#
# Checks that rules/behavioral.md is the single source of truth, that
# CLAUDE.md references (not duplicates) it, and that the hook dynamically
# injects all imperatives at session start.
#
# Exits 0 if all checks pass, 1 otherwise. Output is structured so the
# script is grep-able from a higher-level test harness.
#
# Checks:
#   A. CLAUDE.md references behavioral.md and does not hardcode imperatives.
#   B. The Behavioral rules section precedes the Rules index heading.
#   C. rules/behavioral.md exists, has H1 and numbered H2 sections, and is
#      referenced from CLAUDE.md's rules-index table.
#   D. surface-behavioral-rules.sh exists and is executable.
#   E. The hook is registered in settings.json UserPromptSubmit array.
#   F. Synthetic invocation: hook emits systemMessage containing all
#      imperatives on first call; emits nothing on second call.
#   G. extract-behavioral-rules.sh exists, is executable, and returns output.
#
# Usage: bash ~/.claude/scripts/rules-doctor.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_MD="$REPO_DIR/claude/CLAUDE.md"
BEHAV_MD="$REPO_DIR/claude/rules/behavioral.md"
HOOK="$REPO_DIR/claude/hooks/surface-behavioral-rules.sh"
EXTRACTOR="$REPO_DIR/claude/scripts/extract-behavioral-rules.sh"
SETTINGS="$REPO_DIR/claude/settings.json"

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

# ── A. CLAUDE.md references behavioral.md; does not hardcode imperatives ──
echo "## A. CLAUDE.md behavioral rules section"
if [ -f "$CLAUDE_MD" ]; then
	ok "A.1 CLAUDE.md exists"
	if grep -qF 'rules/behavioral.md' "$CLAUDE_MD"; then
		ok "A.2 CLAUDE.md references rules/behavioral.md"
	else
		fail "A.2 CLAUDE.md references behavioral.md" "link not found"
	fi
	if [ -f "$BEHAV_MD" ]; then
		HARDCODED=0
		while IFS= read -r imperative; do
			if grep -qF -- "$imperative" "$CLAUDE_MD"; then
				HARDCODED=$((HARDCODED + 1))
				fail "A.3 CLAUDE.md hardcodes imperative" "$imperative"
			fi
		done < <(grep -E '^## [0-9]+\. ' "$BEHAV_MD" | sed 's/^## [0-9]*\. //' || true)
		if [ "$HARDCODED" -eq 0 ]; then
			ok "A.3 CLAUDE.md has no hardcoded imperative list"
		fi
	fi
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
	# Skip optional YAML frontmatter and blank lines, then check first
	# non-empty content line is an H1.
	FIRST_CONTENT=$(awk '
		NR==1 && /^---$/  { fm=1; next }
		fm && /^---$/     { fm=0; next }
		fm                { next }
		/^[[:space:]]*$/  { next }
		                  { print; exit }
	' "$BEHAV_MD")
	if printf '%s' "$FIRST_CONTENT" | grep -qE '^# '; then
		ok "C.2 has H1 title"
	else
		fail "C.2 H1 title" "first non-frontmatter line is not '# Title'"
	fi
	H2_CT=$(grep -cE '^## [0-9]+\.' "$BEHAV_MD" || true)
	if [ "${H2_CT:-0}" -ge 1 ]; then
		ok "C.3 has $H2_CT numbered H2 sections"
	else
		fail "C.3 H2 sections" "expected at least 1, found $H2_CT"
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
		if [ -x "$EXTRACTOR" ]; then
			while IFS= read -r imperative; do
				if ! printf '%s' "$MSG" | grep -qF -- "$imperative"; then
					MISSING=$((MISSING + 1))
					fail "F.2 systemMessage line" "missing: $imperative"
				fi
			done < <(bash "$EXTRACTOR" 2>/dev/null | sed 's/^[0-9]*\. //' || true)
		fi
		if [ "$MISSING" -eq 0 ]; then
			ok "F.2 systemMessage contains all behavioral.md imperatives"
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

# ── G. extract-behavioral-rules.sh ────────────────────────────────────────
echo "## G. extract-behavioral-rules.sh"
if [ -f "$EXTRACTOR" ]; then
	ok "G.1 extractor exists"
	if [ -x "$EXTRACTOR" ]; then
		ok "G.2 extractor is executable"
	else
		fail "G.2 extractor executable bit" "chmod +x $EXTRACTOR"
	fi
	EXTRACTED=$(bash "$EXTRACTOR" 2>/dev/null || true)
	if [ -n "$EXTRACTED" ]; then
		ok "G.3 extractor returns output"
	else
		fail "G.3 extractor output" "returned empty; check $BEHAV_MD"
	fi
else
	fail "G.1 extractor exists" "missing: $EXTRACTOR"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "rules-doctor: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
