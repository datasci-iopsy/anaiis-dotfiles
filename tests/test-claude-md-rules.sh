#!/usr/bin/env bash
# tests/test-claude-md-rules.sh, verification harness for the rules system
# (CLAUDE.md index ↔ rules/*.md ↔ settings.json ↔ rules-doctor.sh).
#
# This harness is self-testing: it runs the doctor on the green tree,
# then mutates each input in turn to confirm the doctor catches drift,
# then restores. Each mutation targets one doctor check, so a doctor
# check that can never fail is surfaced here. Exits 0 on full pass.
#
# Usage: bash tests/test-claude-md-rules.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_DIR/claude/scripts/rules-doctor.sh"
CLAUDE_MD="$REPO_DIR/claude/CLAUDE.md"
SETTINGS="$REPO_DIR/claude/settings.json"
BEHAV_MD="$REPO_DIR/claude/rules/behavioral.md"

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
		printf '  FAIL  %s\n        expected to contain: %s\n' "$name" "$needle"
		FAIL=$((FAIL + 1))
	fi
}

# Backup files we will mutate, restore on EXIT (even on early failure).
BACKUP_CLAUDE_MD=$(mktemp)
BACKUP_SETTINGS=$(mktemp)
BACKUP_BEHAV=$(mktemp)
cp "$CLAUDE_MD" "$BACKUP_CLAUDE_MD"
cp "$SETTINGS" "$BACKUP_SETTINGS"
cp "$BEHAV_MD" "$BACKUP_BEHAV"
trap 'cp "$BACKUP_CLAUDE_MD" "$CLAUDE_MD"; cp "$BACKUP_SETTINGS" "$SETTINGS"; cp "$BACKUP_BEHAV" "$BEHAV_MD"; rm -f "$BACKUP_CLAUDE_MD" "$BACKUP_SETTINGS" "$BACKUP_BEHAV"' EXIT

# ── 1. Doctor passes on green tree ────────────────────────────────────────
echo "# 1. Doctor on green tree"
bash "$DOCTOR" >/tmp/test-rules.green.out 2>&1
assert "1.1 doctor exits 0 on green tree" "0" "$?"
assert_contains "1.2 green output reports 0 failures" "0 failed" "$(cat /tmp/test-rules.green.out)"

# ── 2. Doctor catches a dangling index reference (check A.2) ──────────────
echo "# 2. Dangling reference in CLAUDE.md"
printf '\n| `rules/nonexistent-rule.md` | bogus row for drift test |\n' >>"$CLAUDE_MD"
bash "$DOCTOR" >/tmp/test-rules.dangling.out 2>&1
assert "2.1 doctor exits non-zero on dangling reference" "1" "$?"
assert_contains "2.2 doctor names the missing file" "nonexistent-rule.md" "$(cat /tmp/test-rules.dangling.out)"
cp "$BACKUP_CLAUDE_MD" "$CLAUDE_MD"

# ── 3. Doctor catches behavioral.md losing its imperatives (check C.3) ────
echo "# 3. behavioral.md drift"
sed '/^## [0-9]*\. /d' "$BEHAV_MD" >"${BEHAV_MD}.tmp" && mv "${BEHAV_MD}.tmp" "$BEHAV_MD"
bash "$DOCTOR" >/tmp/test-rules.mangled.out 2>&1
assert "3.1 doctor exits non-zero when imperatives removed" "1" "$?"
assert_contains "3.2 doctor reports C.3 imperative count" "C.3 H2 imperatives" "$(cat /tmp/test-rules.mangled.out)"
cp "$BACKUP_BEHAV" "$BEHAV_MD"

# ── 4. Doctor catches a re-injection hook (check D.1) ─────────────────────
echo "# 4. Re-injection registered in settings.json"
if command -v jq >/dev/null 2>&1; then
	jq '.hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/surface-behavioral-rules.sh"}]}]' \
		"$SETTINGS" >/tmp/test-rules.settings.json \
		&& mv /tmp/test-rules.settings.json "$SETTINGS"
	bash "$DOCTOR" >/tmp/test-rules.reinject.out 2>&1
	assert "4.1 doctor exits non-zero on re-injection hook" "1" "$?"
	assert_contains "4.2 doctor reports D.1 re-injection" "D.1 re-injection" "$(cat /tmp/test-rules.reinject.out)"
	cp "$BACKUP_SETTINGS" "$SETTINGS"
else
	echo "  SKIP  jq not available"
fi

# ── 5. Doctor catches a registered-but-missing hook (check E.1) ───────────
echo "# 5. Stale hook registration"
if command -v jq >/dev/null 2>&1; then
	jq '.hooks.Stop += [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/no-such-hook.sh"}]}]' \
		"$SETTINGS" >/tmp/test-rules.settings.json \
		&& mv /tmp/test-rules.settings.json "$SETTINGS"
	bash "$DOCTOR" >/tmp/test-rules.stale.out 2>&1
	assert "5.1 doctor exits non-zero on missing hook file" "1" "$?"
	assert_contains "5.2 doctor names the missing hook" "no-such-hook.sh" "$(cat /tmp/test-rules.stale.out)"
	cp "$BACKUP_SETTINGS" "$SETTINGS"
else
	echo "  SKIP  jq not available"
fi

# ── 5b. Doctor catches a removed secrets deny rule (check H.1) ────────────
echo "# 5b. Missing secrets deny rule"
if command -v jq >/dev/null 2>&1; then
	jq '.permissions.deny -= ["Read(**/.ssh/**)"]' "$SETTINGS" >/tmp/test-rules.settings.json \
		&& mv /tmp/test-rules.settings.json "$SETTINGS"
	bash "$DOCTOR" >/tmp/test-rules.denydrop.out 2>&1
	assert "5b.1 doctor exits non-zero on dropped deny rule" "1" "$?"
	assert_contains "5b.2 doctor names the missing rule" "Read(**/.ssh/**)" "$(cat /tmp/test-rules.denydrop.out)"
	cp "$BACKUP_SETTINGS" "$SETTINGS"
else
	echo "  SKIP  jq not available"
fi

# ── 6. Doctor passes again after all restores ─────────────────────────────
echo "# 6. Restore"
bash "$DOCTOR" >/dev/null 2>&1
assert "6.1 doctor exits 0 after restore" "0" "$?"

# ── Cleanup tmp files ─────────────────────────────────────────────────────
rm -f /tmp/test-rules.green.out /tmp/test-rules.dangling.out \
	/tmp/test-rules.mangled.out /tmp/test-rules.reinject.out /tmp/test-rules.stale.out

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "test-claude-md-rules: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
