#!/usr/bin/env bash
# tests/test-claude-md-rules.sh, verification harness for the
# behavioral-rules pipeline (CLAUDE.md ↔ rules/behavioral.md ↔ hook ↔
# settings.json ↔ rules-doctor.sh).
#
# This harness is self-testing: it runs the doctor on the green tree,
# then mutates each input in turn to confirm the doctor catches drift,
# then restores. Exits 0 on full pass; non-zero on first failure.
#
# Usage: bash tests/test-claude-md-rules.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_DIR/claude/scripts/rules-doctor.sh"
CLAUDE_MD="$REPO_DIR/claude/CLAUDE.md"
SETTINGS="$REPO_DIR/claude/settings.json"

PASS=0
FAIL=0

assert() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' \
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

# Backup files we will mutate, restore on EXIT (even on early failure).
BACKUP_CLAUDE_MD=$(mktemp)
BACKUP_SETTINGS=$(mktemp)
cp "$CLAUDE_MD" "$BACKUP_CLAUDE_MD"
cp "$SETTINGS" "$BACKUP_SETTINGS"
trap 'cp "$BACKUP_CLAUDE_MD" "$CLAUDE_MD"; cp "$BACKUP_SETTINGS" "$SETTINGS"; rm -f "$BACKUP_CLAUDE_MD" "$BACKUP_SETTINGS"' EXIT

# ── 1. Doctor passes on green tree ────────────────────────────────────────
echo "# 1. Doctor on green tree"
bash "$DOCTOR" >/tmp/test-rules.green.out 2>&1
assert "1.1 doctor exits 0 on green tree" "0" "$?"
assert_contains "1.2 green output reports 0 failures" "0 failed" "$(cat /tmp/test-rules.green.out)"

# ── 2. Doctor fails when behavioral.md loses its imperatives ──────────────
echo "# 2. Doctor catches behavioral.md drift"
BEHAV_MD="$REPO_DIR/claude/rules/behavioral.md"
BACKUP_BEHAV=$(mktemp)
cp "$BEHAV_MD" "$BACKUP_BEHAV"
trap 'cp "$BACKUP_CLAUDE_MD" "$CLAUDE_MD"; cp "$BACKUP_SETTINGS" "$SETTINGS"; cp "$BACKUP_BEHAV" "$BEHAV_MD"; rm -f "$BACKUP_CLAUDE_MD" "$BACKUP_SETTINGS" "$BACKUP_BEHAV"' EXIT
# Remove all numbered H2 headings to simulate a corrupted/emptied source file.
sed '/^## [0-9]*\. /d' "$BEHAV_MD" >"${BEHAV_MD}.tmp" && mv "${BEHAV_MD}.tmp" "$BEHAV_MD"
bash "$DOCTOR" >/tmp/test-rules.mangled.out 2>&1
EXIT_MANGLED=$?
assert "2.1 doctor exits non-zero when imperatives removed" "1" "$EXIT_MANGLED"
assert_contains "2.2 doctor reports G.3 extractor empty" "G.3 extractor output" "$(cat /tmp/test-rules.mangled.out)"
cp "$BACKUP_BEHAV" "$BEHAV_MD"

# ── 3. Doctor passes again after behavioral.md restore ────────────────────
echo "# 3. Restore behavioral.md"
bash "$DOCTOR" >/dev/null 2>&1
assert "3.1 doctor exits 0 after restore" "0" "$?"

# ── 4. Doctor fails when hook un-registered from settings.json ────────────
echo "# 4. Doctor catches settings.json drift"
if command -v jq >/dev/null 2>&1; then
	jq 'del(.hooks.UserPromptSubmit[0])' "$SETTINGS" >/tmp/test-rules.settings.json
	mv /tmp/test-rules.settings.json "$SETTINGS"
	bash "$DOCTOR" >/tmp/test-rules.unreg.out 2>&1
	EXIT_UNREG=$?
	assert "4.1 doctor exits non-zero when hook un-registered" "1" "$EXIT_UNREG"
	assert_contains "4.2 doctor reports E.1 registration failure" "E.1 registration" "$(cat /tmp/test-rules.unreg.out)"
	cp "$BACKUP_SETTINGS" "$SETTINGS"
else
	echo "  SKIP  jq not available"
fi

# ── 5. Doctor passes again after settings.json restore ────────────────────
echo "# 5. Restore settings.json"
bash "$DOCTOR" >/dev/null 2>&1
assert "5.1 doctor exits 0 after restore" "0" "$?"

# ── 6. Hook payload covers all behavioral.md imperatives ─────────────────
echo "# 6. Hook payload covers all behavioral.md imperatives"
BEHAV_MD="$REPO_DIR/claude/rules/behavioral.md"
BEHAV_HOOK="$REPO_DIR/claude/hooks/surface-behavioral-rules.sh"
if [ -x "$BEHAV_HOOK" ] && [ -f "$BEHAV_MD" ] && command -v jq >/dev/null 2>&1; then
	TEST_SID6="test6-$$-$RANDOM"
	MARKER6="/tmp/claude-session-${TEST_SID6}.behavioral-loaded"
	rm -f "$MARKER6"
	INPUT6=$(jq -n --arg sid "$TEST_SID6" \
		'{"session_id":$sid,"hook_event_name":"UserPromptSubmit","prompt":"x"}')
	OUT6=$(printf '%s' "$INPUT6" | bash "$BEHAV_HOOK" 2>/dev/null || true)
	rm -f "$MARKER6"
	MSG6=$(printf '%s' "$OUT6" | jq -r '.systemMessage' 2>/dev/null || true)
	while IFS= read -r imperative; do
		assert_contains "6.1 hook includes: $imperative" "$imperative" "$MSG6"
	done < <(grep -E '^## [0-9]+\. ' "$BEHAV_MD" | sed 's/^## [0-9]*\. //')
else
	echo "  SKIP  hook, behavioral.md, or jq missing"
fi

# ── 7. CLAUDE.md does not hardcode the imperative list ────────────────────
echo "# 7. CLAUDE.md does not hardcode imperative list"
while IFS= read -r imperative; do
	FOUND="absent"
	grep -qF -- "$imperative" "$CLAUDE_MD" 2>/dev/null && FOUND="present"
	assert "7.1 CLAUDE.md no inline: $imperative" "absent" "$FOUND"
done < <(grep -E '^## [0-9]+\. ' "$REPO_DIR/claude/rules/behavioral.md" | sed 's/^## [0-9]*\. //')

# ── Cleanup tmp files ─────────────────────────────────────────────────────
rm -f /tmp/test-rules.green.out /tmp/test-rules.mangled.out /tmp/test-rules.unreg.out

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "test-claude-md-rules: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
