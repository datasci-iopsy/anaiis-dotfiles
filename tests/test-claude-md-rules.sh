#!/usr/bin/env bash
# tests/test-claude-md-rules.sh, verification harness for the rules system
# (CLAUDE.md index <-> rules/*.md <-> settings.json <-> rules-doctor.sh).
#
# Self-testing: run the doctor on a green tree, then apply every drift
# mutation at once and confirm the doctor names each targeted check. One
# multi-fault run rather than one run per fault: the doctor runs every check
# and never exits early, so each name assertion pins its own check (deleting
# check X removes the "X" line from the output), and a single exit-code
# assertion covers the shared FAIL plumbing. The per-fault exit-code
# assertions this replaced could not fail independently of the name
# assertions (tasks/trim-candidates.md, 2026-09-07).
#
# Hermetic: the doctor runs against a throwaway copy of claude/ via
# RULES_DOCTOR_REPO_DIR. The real claude/CLAUDE.md, claude/rules/, and
# claude/settings.json (live through the ~/.claude symlink) are never
# touched, so a concurrent Claude Code session cannot observe a mutated
# settings file mid-test.
#
# Usage: bash tests/test-claude-md-rules.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_DIR/claude/scripts/rules-doctor.sh"

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

# ── Fixture: throwaway copy of claude/ ────────────────────────────────────
# -P keeps claude/skills' symlinks as symlinks instead of copying targets.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
TMP_REPO="$WORK/repo"
mkdir -p "$TMP_REPO"
cp -RP "$REPO_DIR/claude" "$TMP_REPO/claude"
CLAUDE_MD="$TMP_REPO/claude/CLAUDE.md"
SETTINGS="$TMP_REPO/claude/settings.json"
BEHAV_MD="$TMP_REPO/claude/rules/behavioral.md"

run_doctor() {
	RULES_DOCTOR_REPO_DIR="$TMP_REPO" bash "$DOCTOR" >"$1" 2>&1
}

# ── 1. Doctor passes on green tree ────────────────────────────────────────
echo "# 1. Doctor on green tree"
run_doctor "$WORK/green.out"
assert "1.1 doctor exits 0 on green tree" "0" "$?"

# ── 2. Every drift mutation at once ───────────────────────────────────────
echo "# 2. Every drift mutation applied at once"
# A.2: index row pointing at a rules file that does not exist
printf '\n| `rules/nonexistent-rule.md` | bogus row for drift test |\n' >>"$CLAUDE_MD"
# C.3: behavioral.md loses its numbered H2 imperatives
sed '/^## [0-9]*\. /d' "$BEHAV_MD" >"${BEHAV_MD}.tmp" && mv "${BEHAV_MD}.tmp" "$BEHAV_MD"
HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then
	HAVE_JQ=1
	# D.1: a re-injection hook registered on UserPromptSubmit
	# E.1: a registered hook whose file does not exist
	# H.1: a secrets deny rule dropped from permissions.deny
	jq '.hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/surface-behavioral-rules.sh"}]}]
		| .hooks.Stop += [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/no-such-hook.sh"}]}]
		| .permissions.deny -= ["Read(**/.ssh/**)"]' \
		"$SETTINGS" >"$WORK/settings.json" && mv "$WORK/settings.json" "$SETTINGS"
fi
run_doctor "$WORK/faults.out"
RC=$?
OUT=$(cat "$WORK/faults.out")
assert "2.1 doctor exits non-zero with every fault present" "1" "$RC"
assert_contains "2.2 doctor names the missing rules file (A.2)" "nonexistent-rule.md" "$OUT"
assert_contains "2.3 doctor reports the imperative count (C.3)" "C.3 H2 imperatives" "$OUT"
if [ "$HAVE_JQ" -eq 1 ]; then
	assert_contains "2.4 doctor reports re-injection (D.1)" "D.1 re-injection" "$OUT"
	assert_contains "2.5 doctor names the missing hook (E.1)" "no-such-hook.sh" "$OUT"
	assert_contains "2.6 doctor names the dropped deny rule (H.1)" "Read(**/.ssh/**)" "$OUT"
else
	echo "  SKIP  2.4-2.6 jq not available"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "test-claude-md-rules: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
