#!/usr/bin/env bash
# tests/test-claude-md-rules.sh — verification harness for the
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
bash "$DOCTOR" > /tmp/test-rules.green.out 2>&1
assert "1.1 doctor exits 0 on green tree" "0" "$?"
assert_contains "1.2 green output reports 0 failures" "0 failed" "$(cat /tmp/test-rules.green.out)"

# ── 2. Doctor fails when CLAUDE.md missing a behavioral line ──────────────
echo "# 2. Doctor catches CLAUDE.md drift"
sed -i.bak "s/Don't assume. Don't hide confusion. Surface tradeoffs./MUTATED/" "$CLAUDE_MD"
rm -f "${CLAUDE_MD}.bak"
bash "$DOCTOR" > /tmp/test-rules.mangled.out 2>&1
EXIT_MANGLED=$?
assert "2.1 doctor exits non-zero when line mutated" "1" "$EXIT_MANGLED"
assert_contains "2.2 doctor reports A.2 missing line" "A.2 CLAUDE.md missing line" "$(cat /tmp/test-rules.mangled.out)"
cp "$BACKUP_CLAUDE_MD" "$CLAUDE_MD"

# ── 3. Doctor passes again after CLAUDE.md restore ────────────────────────
echo "# 3. Restore CLAUDE.md"
bash "$DOCTOR" > /dev/null 2>&1
assert "3.1 doctor exits 0 after restore" "0" "$?"

# ── 4. Doctor fails when hook un-registered from settings.json ────────────
echo "# 4. Doctor catches settings.json drift"
if command -v jq >/dev/null 2>&1; then
	jq 'del(.hooks.UserPromptSubmit[0])' "$SETTINGS" > /tmp/test-rules.settings.json
	mv /tmp/test-rules.settings.json "$SETTINGS"
	bash "$DOCTOR" > /tmp/test-rules.unreg.out 2>&1
	EXIT_UNREG=$?
	assert "4.1 doctor exits non-zero when hook un-registered" "1" "$EXIT_UNREG"
	assert_contains "4.2 doctor reports E.1 registration failure" "E.1 registration" "$(cat /tmp/test-rules.unreg.out)"
	cp "$BACKUP_SETTINGS" "$SETTINGS"
else
	echo "  SKIP  jq not available"
fi

# ── 5. Doctor passes again after settings.json restore ────────────────────
echo "# 5. Restore settings.json"
bash "$DOCTOR" > /dev/null 2>&1
assert "5.1 doctor exits 0 after restore" "0" "$?"

# ── Cleanup tmp files ─────────────────────────────────────────────────────
rm -f /tmp/test-rules.green.out /tmp/test-rules.mangled.out /tmp/test-rules.unreg.out

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "test-claude-md-rules: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
