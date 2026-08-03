#!/usr/bin/env bash
# tests/test-cost-guard.sh -- verify cost-guard.sh
#
# Confirms: Explore/Plan pass through with info; general-purpose agents are
# counted and blocked above cap; WebFetch passes; COST_GUARD_GP_LIMIT is
# respected; stamp files are managed correctly.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -u

# Isolate from the user's shell config (shared.bash exports this var);
# section 5 tests the default cap, section 6 sets its own value inline.
unset COST_GUARD_GP_LIMIT

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/cost-guard.sh"

PASS=0
FAIL=0

pass() {
	printf '  PASS  %s\n' "$1"
	PASS=$((PASS + 1))
}

fail() {
	printf '  FAIL  %s\n' "$1"
	FAIL=$((FAIL + 1))
}

assert_exit() {
	local label="$1" want="$2" json="$3"
	local got
	got=$(
		printf '%s' "$json" | bash "$HOOK" 2>/dev/null
		echo $?
	)
	if [ "$got" = "$want" ]; then
		pass "$label"
	else
		fail "$label (got exit=$got, want $want)"
	fi
}

assert_stderr_contains() {
	local label="$1" needle="$2" json="$3"
	local stderr_out
	stderr_out=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null)
	if printf '%s' "$stderr_out" | grep -qF "$needle"; then
		pass "$label"
	else
		fail "$label (stderr missing '$needle'; got: ${stderr_out:0:100})"
	fi
}

make_agent_input() {
	local subtype="$1" desc="$2" sid="$3" prompt="${4:-short prompt}"
	printf '{"tool_name":"Agent","session_id":"%s","tool_input":{"subagent_type":"%s","description":"%s","prompt":"%s"}}' \
		"$sid" "$subtype" "$desc" "$prompt"
}

# ── 1. Hook file present and executable ───────────────────────────────────────

echo
echo "--- 1. Hook file"

if [ -f "$HOOK" ]; then
	pass "1.1 hook exists"
else
	fail "1.1 hook missing: $HOOK"
fi

if [ -x "$HOOK" ]; then
	pass "1.2 hook executable"
else
	fail "1.2 hook not executable"
fi

# ── 2. Bounded agents pass through ────────────────────────────────────────────

echo
echo "--- 2. Bounded agents pass (Explore, Plan, claude-code-guide)"

SID_B="cost-test-bounded-$$-$(date +%s)"

assert_exit "2.1 Explore passes" 0 \
	"$(make_agent_input 'Explore' 'find thing' "$SID_B")"
assert_exit "2.2 Plan passes" 0 \
	"$(make_agent_input 'Plan' 'plan task' "$SID_B")"
assert_exit "2.3 claude-code-guide passes" 0 \
	"$(make_agent_input 'claude-code-guide' 'answer question' "$SID_B")"

# ── 3. CodeRabbit surgeon passes through ──────────────────────────────────────

echo
echo "--- 3. Code-surgeon with CR-NNN description passes"

SID_CR="cost-test-cr-$$-$(date +%s)"
STAMP_CR="/tmp/claude-session-${SID_CR}.gp-count"

# Exit 0 alone doesn't prove exemption -- a counted-but-under-cap call also
# exits 0. The stamp file only gets written on the counted (non-exempt) path,
# so its absence after the call is the real signal.
assert_exempt() {
	local label="$1" desc="$2"
	rm -f "$STAMP_CR"
	local exit_code
	exit_code=$(
		printf '%s' "$(make_agent_input 'general-purpose' "$desc" "$SID_CR")" | bash "$HOOK" 2>/dev/null
		echo $?
	)
	if [ "$exit_code" = "0" ] && [ ! -f "$STAMP_CR" ]; then
		pass "$label"
	else
		fail "$label (exit=$exit_code, stamp $([ -f "$STAMP_CR" ] && echo present || echo absent))"
	fi
}

assert_exempt "3.1 Fix CR-123 surgeon exempt from GP count" "Fix CR-123: typo in handler"
assert_exempt "3.2 Fix CR-PR-11-3699782339 (PR-mode id) surgeon exempt from GP count" "Fix CR-PR-11-3699782339: typo in handler"
assert_exempt "3.3 Fix CR-PR-11-123,PR-11-456 (batched PR-mode ids) surgeon exempt from GP count" "Fix CR-PR-11-123,PR-11-456: shared file"

rm -f "$STAMP_CR"

# ── 4. General-purpose agents below cap are counted and allowed ───────────────

echo
echo "--- 4. GP agents below cap pass"

SID_GP="cost-test-gp-$$-$(date +%s)"
STAMP="/tmp/claude-session-${SID_GP}.gp-count"
rm -f "$STAMP"

assert_exit "4.1 GP spawn #1 passes" 0 \
	"$(make_agent_input 'general-purpose' 'do research' "$SID_GP")"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "1" ]; then
	pass "4.2 stamp file created with count=1"
else
	fail "4.2 stamp file missing or wrong (content: $(cat "$STAMP" 2>/dev/null || echo 'absent'))"
fi

assert_exit "4.3 GP spawn #2 passes" 0 \
	"$(make_agent_input 'general-purpose' 'more research' "$SID_GP")"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "2" ]; then
	pass "4.4 stamp incremented to 2"
else
	fail "4.4 stamp not incremented (content: $(cat "$STAMP" 2>/dev/null || echo 'absent'))"
fi

rm -f "$STAMP"

# ── 5. GP agents at cap are blocked ───────────────────────────────────────────

echo
echo "--- 5. GP agents above cap are blocked"

SID_CAP="cost-test-cap-$$-$(date +%s)"
STAMP_CAP="/tmp/claude-session-${SID_CAP}.gp-count"
# Pre-seed at the default cap (10) so next spawn is #11 (exceeds limit)
echo "10" >"$STAMP_CAP"

assert_exit "5.1 GP spawn #11 blocked when cap=10" 2 \
	"$(make_agent_input 'general-purpose' 'over-cap task' "$SID_CAP")"

assert_stderr_contains "5.2 block message emitted" "COST GATE BLOCK" \
	"$(make_agent_input 'general-purpose' 'over-cap task' "$SID_CAP")"

rm -f "$STAMP_CAP"

# ── 6. COST_GUARD_GP_LIMIT env var is respected ───────────────────────────────

echo
echo "--- 6. COST_GUARD_GP_LIMIT override"

SID_LIM="cost-test-lim-$$-$(date +%s)"
STAMP_LIM="/tmp/claude-session-${SID_LIM}.gp-count"
echo "2" >"$STAMP_LIM"

# With custom limit=2, spawn #3 should be blocked
got=$(
	printf '%s' "$(make_agent_input 'general-purpose' 'third task' "$SID_LIM")" \
		| COST_GUARD_GP_LIMIT=2 bash "$HOOK" 2>/dev/null
	echo $?
)
if [ "$got" = "2" ]; then
	pass "6.1 COST_GUARD_GP_LIMIT=2 blocks spawn #3"
else
	fail "6.1 COST_GUARD_GP_LIMIT=2 should block spawn #3 (got exit=$got)"
fi

rm -f "$STAMP_LIM"

# ── 7. WebFetch passes through ────────────────────────────────────────────────

echo
echo "--- 7. WebFetch passes"

assert_exit "7.1 WebFetch passes" 0 \
	'{"tool_name":"WebFetch","tool_input":{"url":"https://example.com","prompt":"get"}}'

# ── 8. Non-agent tools pass through ───────────────────────────────────────────

echo
echo "--- 8. Non-agent tools pass"

assert_exit "8.1 Bash passes" 0 \
	'{"tool_name":"Bash","tool_input":{"command":"ls"}}'
assert_exit "8.2 Read passes" 0 \
	'{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
