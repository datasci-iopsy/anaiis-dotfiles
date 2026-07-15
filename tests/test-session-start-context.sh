#!/usr/bin/env bash
# tests/test-session-start-context.sh -- behavioral tests for the consolidated
# SessionStart memory hook (claude/hooks/session-start-context.sh).
#
# Replaces the systemMessage-based assertions in load-global-memory.sh /
# memory-quality-check.sh / post-compact.sh tests: this hook must deliver
# context via hookSpecificOutput.additionalContext, the channel that actually
# reaches the model (systemMessage is display-only, see tmp/memory-system-
# review-2026-07-15.md, gap G1).
#
# Exit 0 if all tests pass; non-zero on any failure.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/session-start-context.sh"

PASS=0
FAIL=0

pass() {
	echo "  PASS  $1"
	PASS=$((PASS + 1))
}
fail() {
	echo "  FAIL  $1"
	FAIL=$((FAIL + 1))
}

assert_eq() {
	local label="$1" got="$2" want="$3"
	[ "$got" = "$want" ] && pass "$label" || fail "$label (got: '$got', want: '$want')"
}

assert_empty() {
	local label="$1" value="$2"
	[ -z "$value" ] && pass "$label" || fail "$label (expected empty, got: ${value:0:120})"
}

assert_contains() {
	local label="$1" haystack="$2" needle="$3"
	printf '%s' "$haystack" | grep -qF "$needle" && pass "$label" || fail "$label (missing: $needle)"
}

if [ ! -f "$HOOK" ]; then
	echo "  FAIL  hook not found at $HOOK"
	echo
	echo "============================================================"
	echo "  Tests passed: 0"
	echo "  Tests failed: 1"
	exit 1
fi

make_input() {
	local source="$1" sid="$2" cwd="$3"
	jq -n --arg src "$source" --arg sid "$sid" --arg cwd "$cwd" \
		'{"source": $src, "session_id": $sid, "cwd": $cwd, "hook_event_name": "SessionStart"}'
}

# ---- T1: startup emits hookSpecificOutput.additionalContext, not systemMessage-only ----

echo
echo "--- T1: startup source emits additionalContext channel"

T1_HOME=$(mktemp -d)
T1_PROJ=$(mktemp -d)
mkdir -p "$T1_HOME/.claude/memory"
cat >"$T1_HOME/.claude/memory/MEMORY.md" <<'MEMEOF'
# Global Memory Index

- [User profile](user_profile.md): test user facts
MEMEOF
cat >"$T1_HOME/.claude/memory/user_profile.md" <<'PROFEOF'
---
name: user-profile
description: test user facts
type: user
---

Test user, senior engineer.
PROFEOF

T1_RESULT=$(make_input "startup" "t1-$$" "$T1_PROJ" | HOME="$T1_HOME" bash "$HOOK" 2>/dev/null)
rm -rf "$T1_HOME" "$T1_PROJ"

if [ -n "$T1_RESULT" ]; then
	T1_CTX=$(printf '%s' "$T1_RESULT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
	T1_EVT=$(printf '%s' "$T1_RESULT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
	assert_eq "T1a: hookEventName is SessionStart" "$T1_EVT" "SessionStart"
	assert_contains "T1b: additionalContext carries the profile content" "$T1_CTX" "Test user, senior engineer."
	# The bug being fixed: a systemMessage-only payload (no hookSpecificOutput) never reaches
	# the model. Assert the OLD dead-channel shape is NOT what carries the real payload.
	T1_SYSMSG=$(printf '%s' "$T1_RESULT" | jq -r '.systemMessage // ""' 2>/dev/null)
	if printf '%s' "$T1_SYSMSG" | grep -qF "Test user, senior engineer."; then
		fail "T1c: full payload must not ride only in systemMessage (display-only, never reaches the model)"
	else
		pass "T1c: full payload is not systemMessage-only"
	fi
else
	fail "T1: hook emitted nothing on startup with a populated global tier"
fi

# ---- T2: resume source emits nothing (already in the resumed transcript) ----

echo
echo "--- T2: resume source is a no-op"

T2_HOME=$(mktemp -d)
T2_PROJ=$(mktemp -d)
mkdir -p "$T2_HOME/.claude/memory"
echo "# Global Memory Index" >"$T2_HOME/.claude/memory/MEMORY.md"

T2_RESULT=$(make_input "resume" "t2-$$" "$T2_PROJ" | HOME="$T2_HOME" bash "$HOOK" 2>/dev/null)
rm -rf "$T2_HOME" "$T2_PROJ"
assert_empty "T2: resume source emits nothing" "$T2_RESULT"

# ---- T3: hyphenated filenames in the index are loaded (G10 regression guard) ----

echo
echo "--- T3: hyphenated linked filenames load (G10)"

T3_HOME=$(mktemp -d)
T3_PROJ=$(mktemp -d)
mkdir -p "$T3_HOME/.claude/memory"
cat >"$T3_HOME/.claude/memory/MEMORY.md" <<'MEMEOF'
# Global Memory Index

- [Hyphen fact](some-fact.md): a fact whose filename has a hyphen
MEMEOF
cat >"$T3_HOME/.claude/memory/some-fact.md" <<'FACTEOF'
---
name: some-fact
description: hyphen filename regression guard
type: feedback
---

HYPHEN_MARKER_CONTENT
FACTEOF

T3_RESULT=$(make_input "startup" "t3-$$" "$T3_PROJ" | HOME="$T3_HOME" bash "$HOOK" 2>/dev/null)
rm -rf "$T3_HOME" "$T3_PROJ"

T3_CTX=$(printf '%s' "$T3_RESULT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "T3: hyphenated filename's content is included" "$T3_CTX" "HYPHEN_MARKER_CONTENT"

# ---- T4: compact source restores the newest handoff ----

echo
echo "--- T4: compact source restores newest handoff"

T4_HOME=$(mktemp -d)
T4_PROJ=$(mktemp -d)
T4_KEY=$(printf '%s' "$T4_PROJ" | tr '/.' '-')
T4_HANDOFFS="$T4_HOME/.claude/projects/$T4_KEY/memory/handoffs"
mkdir -p "$T4_HANDOFFS" "$T4_HOME/.claude/memory"
echo "# Global Memory Index" >"$T4_HOME/.claude/memory/MEMORY.md"
echo "OLD_HANDOFF_MARKER" >"$T4_HANDOFFS/handoff_2026-01-01T00-00Z_aaaaa.md"
echo "NEWEST_HANDOFF_MARKER" >"$T4_HANDOFFS/handoff_2026-06-01T00-00Z_bbbbb.md"

T4_RESULT=$(make_input "compact" "t4-$$" "$T4_PROJ" | HOME="$T4_HOME" bash "$HOOK" 2>/dev/null)
rm -rf "$T4_HOME" "$T4_PROJ"

T4_CTX=$(printf '%s' "$T4_RESULT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "T4: newest handoff content present" "$T4_CTX" "NEWEST_HANDOFF_MARKER"
if printf '%s' "$T4_CTX" | grep -qF "OLD_HANDOFF_MARKER"; then
	fail "T4b: only the newest handoff should be restored, not the older one"
else
	pass "T4b: older handoff correctly excluded"
fi

# ---- T5: missing project memory triggers a seed advisory ----

echo
echo "--- T5: missing project memory dir advises /seed-project"

T5_HOME=$(mktemp -d)
T5_PROJ=$(mktemp -d)
mkdir -p "$T5_HOME/.claude/memory"
echo "# Global Memory Index" >"$T5_HOME/.claude/memory/MEMORY.md"

T5_RESULT=$(make_input "startup" "t5-$$" "$T5_PROJ" | HOME="$T5_HOME" bash "$HOOK" 2>/dev/null)
rm -rf "$T5_HOME" "$T5_PROJ"

T5_CTX=$(printf '%s' "$T5_RESULT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "T5: seed-project advisory present when project memory absent" "$T5_CTX" "/seed-project"

# ---- T6: compact with no MEMORY.md or handoff exits 0 silently ----

echo
echo "--- T6: compact with no MEMORY.md or handoff exits 0 silently"

T6_HOME=$(mktemp -d)
T6_PROJ=$(mktemp -d)
mkdir -p "$T6_HOME/.claude"

T6_RESULT=$(make_input "compact" "t6-$$" "$T6_PROJ" | HOME="$T6_HOME" bash "$HOOK" 2>/dev/null)
rm -rf "$T6_HOME" "$T6_PROJ"
assert_empty "T6: no output when nothing to deliver" "$T6_RESULT"

# ---- T7: pressure - missing jq exits 0 silently ----

echo
echo "--- T7: pressure - missing jq exits 0 silently"

T7_HOME=$(mktemp -d)
T7_PROJ=$(mktemp -d)
mkdir -p "$T7_HOME/.claude/memory"
echo "# Global Memory Index" >"$T7_HOME/.claude/memory/MEMORY.md"

T7_RESULT=$(make_input "startup" "t7-$$" "$T7_PROJ" \
	| HOME="$T7_HOME" PATH="/bin" bash "$HOOK" 2>/dev/null) || true
rm -rf "$T7_HOME" "$T7_PROJ"
assert_empty "T7: no output when jq absent from PATH" "$T7_RESULT"

# ---- T8: staleness stamp advances only when an advisory was actually emitted (G2) ----

echo
echo "--- T8: staleness stamp is delivery-gated (G2)"

T8_HOME=$(mktemp -d)
T8_PROJ=$(mktemp -d)
mkdir -p "$T8_HOME/.claude/memory" "$T8_HOME/.claude/projects/$(printf '%s' "$T8_PROJ" | tr '/.' '-')/memory"
echo "# Global Memory Index" >"$T8_HOME/.claude/memory/MEMORY.md"
# Force the monthly gate open (stamp far in the past) but with a fresh (non-stale) file,
# so no advisory content exists to emit.
echo "2020-01-01" >"$T8_HOME/.claude/.maintenance-memory-quality"

make_input "startup" "t8-$$" "$T8_PROJ" | HOME="$T8_HOME" bash "$HOOK" >/dev/null 2>&1 || true
T8_STAMP_AFTER=$(cat "$T8_HOME/.claude/.maintenance-memory-quality" 2>/dev/null || echo "")
rm -rf "$T8_HOME" "$T8_PROJ"

assert_eq "T8: stamp untouched when no stale files found (nothing was emitted)" "$T8_STAMP_AFTER" "2020-01-01"

# ---- T9: staleness scan works when GLOBAL_DIR is a symlink (regression) ----
#
# BSD find (macOS default) does not descend into a symlink given as its own
# starting path argument unless -L is passed. The production global tier
# (~/.claude/memory) IS such a symlink; the T8 sandbox above uses a plain
# directory and could never have caught this. This test builds a real
# symlink to prove the staleness scan finds files through it.

echo
echo "--- T9: staleness scan traverses a symlinked GLOBAL_DIR (regression guard)"

T9_HOME=$(mktemp -d)
T9_REAL_TARGET=$(mktemp -d)
T9_PROJ=$(mktemp -d)
mkdir -p "$T9_HOME/.claude"
ln -s "$T9_REAL_TARGET" "$T9_HOME/.claude/memory"
echo "# Global Memory Index" >"$T9_HOME/.claude/memory/MEMORY.md"
printf -- '---\nname: stale-fixture\ndescription: test\nmetadata:\n  type: feedback\n---\n\nstale\n' \
	>"$T9_HOME/.claude/memory/stale_fixture.md"
# Non-git file with an old mtime falls to the mtime path (git_ts lookup fails silently).
touch -t 202001010000 "$T9_HOME/.claude/memory/stale_fixture.md" 2>/dev/null
echo "2020-01-01" >"$T9_HOME/.claude/.maintenance-memory-quality"

T9_RESULT=$(make_input "startup" "t9-$$" "$T9_PROJ" | HOME="$T9_HOME" bash "$HOOK" 2>/dev/null)
T9_STAMP_AFTER=$(cat "$T9_HOME/.claude/.maintenance-memory-quality" 2>/dev/null || echo "")
rm -rf "$T9_HOME" "$T9_REAL_TARGET" "$T9_PROJ"

T9_CTX=$(printf '%s' "$T9_RESULT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "T9a: stale file found through a symlinked GLOBAL_DIR" "$T9_CTX" "stale_fixture.md"
assert_eq "T9b: stamp advances once the advisory is genuinely emitted" "$T9_STAMP_AFTER" "$(date +%Y-%m-%d)"

# ---- Summary ----------------------------------------------------------------

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
