#!/usr/bin/env bash
# tests/test-migrate-memory-guard.sh -- migrate-memory.sh safety guards (T4.2)
#
# The 2026-07-15 memory-system review demonstrated that seeding a project
# from claude/memory-templates/ then running migrate-memory.sh could clobber
# a curated global memory file: the template's user_profile.md stub gets a
# newer mtime than the curated global file, and migrate-memory.sh's
# newer-mtime-wins promotion logic would overwrite the real file with the
# stub. This test proves that scenario is now blocked, and that migration
# defaults to a dry-run requiring an explicit --apply to mutate anything.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_DIR/claude/scripts/migrate-memory.sh"

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

if [ ! -f "$SCRIPT" ]; then
	echo "  FAIL  script not found at $SCRIPT"
	echo
	echo "============================================================"
	echo "  Tests passed: 0"
	echo "  Tests failed: 1"
	exit 1
fi

# ---- T1: default invocation (no flags) is dry-run, mutates nothing --------

echo
echo "--- T1: default invocation (no flags) does not mutate"

T1_HOME=$(mktemp -d)
T1_PROJ=$(mktemp -d)
mkdir -p "$T1_HOME/.claude/memory" "$T1_PROJ/memory"
CURATED_CONTENT="---
name: user-profile
description: curated real profile
metadata:
  type: user
---

Curated content that must survive."
printf '%s' "$CURATED_CONTENT" >"$T1_HOME/.claude/memory/user_profile.md"

T1_KEY=$(printf '%s' "$T1_PROJ" | tr '/.' '-')
T1_PROJ_MEM="$T1_HOME/.claude/projects/$T1_KEY/memory"
mkdir -p "$T1_PROJ_MEM"
printf '%s' "DIFFERENT_NEWER_CONTENT" >"$T1_PROJ_MEM/user_profile.md"
# Project copy must be newer than the global copy so a naive "keep newer"
# promotion would definitely fire without the dry-run-by-default guard.
touch -t 203001010000 "$T1_PROJ_MEM/user_profile.md" 2>/dev/null || true

HOME="$T1_HOME" bash "$SCRIPT" >/dev/null 2>&1 || true

assert_eq "T1: curated global file untouched by default (no-flag) invocation" \
	"$(cat "$T1_HOME/.claude/memory/user_profile.md")" "$CURATED_CONTENT"
rm -rf "$T1_HOME" "$T1_PROJ"

# ---- T2: --apply is required to mutate; a genuinely new user-level file is promoted

echo
echo "--- T2: --apply promotes a genuine, non-template user-level file"

T2_HOME=$(mktemp -d)
T2_PROJ=$(mktemp -d)
mkdir -p "$T2_HOME/.claude/memory"
T2_KEY=$(printf '%s' "$T2_PROJ" | tr '/.' '-')
T2_PROJ_MEM="$T2_HOME/.claude/projects/$T2_KEY/memory"
mkdir -p "$T2_PROJ_MEM"
printf '%s' "GENUINE_NEW_USER_FACT_NOT_A_TEMPLATE_STUB" >"$T2_PROJ_MEM/user_something_unique.md"

HOME="$T2_HOME" bash "$SCRIPT" --apply >/dev/null 2>&1 || true

if [ -f "$T2_HOME/.claude/memory/user_something_unique.md" ]; then
	assert_eq "T2: --apply promotes a genuine user-level file with no template match" \
		"$(cat "$T2_HOME/.claude/memory/user_something_unique.md")" \
		"GENUINE_NEW_USER_FACT_NOT_A_TEMPLATE_STUB"
else
	fail "T2: --apply did not promote the genuine user-level file"
fi
rm -rf "$T2_HOME" "$T2_PROJ"

# ---- T3: the review's clobber scenario is now blocked, even with --apply --

echo
echo "--- T3: template-stub content is refused even with --apply (the clobber scenario)"

T3_HOME=$(mktemp -d)
T3_PROJ=$(mktemp -d)
mkdir -p "$T3_HOME/.claude/memory"
printf '%s' "$CURATED_CONTENT" >"$T3_HOME/.claude/memory/user_profile.md"

T3_KEY=$(printf '%s' "$T3_PROJ" | tr '/.' '-')
T3_PROJ_MEM="$T3_HOME/.claude/projects/$T3_KEY/memory"
mkdir -p "$T3_PROJ_MEM"
# Byte-for-byte the retired memory-templates/user_profile.md stub content.
cat >"$T3_PROJ_MEM/user_profile.md" <<'STUBEOF'
---
name: user-project-role
description: User's role and focus within this specific project
type: user
---

**Role in this project:** [fill in -- sole author, contributor, reviewer, etc.]

**Project-specific context:** [any facts about the user's relationship to this codebase that differ from their global profile]
STUBEOF
touch -t 203001010000 "$T3_PROJ_MEM/user_profile.md" 2>/dev/null || true

HOME="$T3_HOME" bash "$SCRIPT" --apply >/dev/null 2>&1 || true

assert_eq "T3: curated global profile survives the clobber scenario under --apply" \
	"$(cat "$T3_HOME/.claude/memory/user_profile.md")" "$CURATED_CONTENT"
rm -rf "$T3_HOME" "$T3_PROJ"

# ---- Summary ----------------------------------------------------------------

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
