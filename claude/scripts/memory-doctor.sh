#!/usr/bin/env bash
# memory-doctor.sh, verify the memory pipeline end to end.
#
# Reports per-project memory health and synthetically exercises the
# load-global-memory and pre/post-compact hooks so problems surface
# without waiting for a real session compaction.
#
# Exits 0 if all checks pass, 1 otherwise. Output is structured so the
# script is grep-able from a higher-level test or schedule.
#
# Checks:
#   A. Global tier present and indexed.
#   B. Each topical file has valid frontmatter (name, description, type).
#   C. Each project memory dir has a handoffs/ subdir; bounded ≤5.
#   D. No flat handoff_*.md sitting at project memory root (migration done).
#   E. load-global-memory hook emits the index on first invocation; nothing on second.
#   F. pre-compact hook places handoff in handoffs/ subdir when invoked synthetically.
#   G. post-compact hook reads from handoffs/ first.
#
# Usage: bash ~/.claude/scripts/memory-doctor.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECTS_DIR="$HOME/.claude/projects"
GLOBAL_DIR="$HOME/.claude/memory"
LOAD_HOOK="$REPO_DIR/claude/hooks/load-global-memory.sh"
PRE_HOOK="$REPO_DIR/claude/hooks/pre-compact.sh"
POST_HOOK="$REPO_DIR/claude/hooks/post-compact.sh"

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

# ── A. Global tier ────────────────────────────────────────────────────────
echo "## A. Global tier"
if [ -d "$GLOBAL_DIR" ]; then
	ok "A.1 global memory directory exists"
else
	fail "A.1 global memory directory exists" "missing: $GLOBAL_DIR"
fi
if [ -f "$GLOBAL_DIR/MEMORY.md" ]; then
	ok "A.2 global MEMORY.md index exists"
else
	fail "A.2 global MEMORY.md index exists" "missing: $GLOBAL_DIR/MEMORY.md"
fi

# ── B. Frontmatter validity across global + project memory ────────────────
echo "## B. Frontmatter integrity"
INVALID_FM=0
INVALID_FILES=()
check_frontmatter() {
	local f="$1"
	[ -f "$f" ] || return 0
	[ "$(basename "$f")" = "MEMORY.md" ] && return 0
	local first_three
	first_three=$(head -3 "$f")
	if [[ "$first_three" != *"name:"*"description:"*"type:"* ]] \
		&& ! (head -10 "$f" | grep -q '^name:' \
			&& head -10 "$f" | grep -q '^description:' \
			&& head -10 "$f" | grep -q '^type:'); then
		INVALID_FM=$((INVALID_FM + 1))
		INVALID_FILES+=("$f")
	fi
}

if [ -d "$GLOBAL_DIR" ]; then
	for f in "$GLOBAL_DIR"/*.md; do check_frontmatter "$f"; done
fi
if [ -d "$PROJECTS_DIR" ]; then
	for f in "$PROJECTS_DIR"/*/memory/*.md; do
		[ "$(basename "$f")" = "MEMORY.md" ] && continue
		check_frontmatter "$f"
	done
fi

if [ "$INVALID_FM" -eq 0 ]; then
	ok "B.1 all topical memory files have name/description/type frontmatter"
else
	fail "B.1 frontmatter integrity" "$INVALID_FM file(s) missing required fields:"
	printf '          %s\n' "${INVALID_FILES[@]}"
fi

# ── C. Per-project handoffs/ subdir bounded at 5 ──────────────────────────
echo "## C. Handoff retention (per-project ≤5)"
OVERFLOW=0
OVERFLOW_DIRS=()
if [ -d "$PROJECTS_DIR" ]; then
	for hd in "$PROJECTS_DIR"/*/memory/handoffs; do
		[ -d "$hd" ] || continue
		cnt=$(find "$hd" -maxdepth 1 -name 'handoff_*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
		if [ "${cnt:-0}" -gt 5 ]; then
			OVERFLOW=$((OVERFLOW + 1))
			OVERFLOW_DIRS+=("$hd ($cnt)")
		fi
	done
fi
if [ "$OVERFLOW" -eq 0 ]; then
	ok "C.1 all project handoffs/ subdirs at or under cap of 5"
else
	fail "C.1 handoff cap" "$OVERFLOW project(s) over cap:"
	printf '          %s\n' "${OVERFLOW_DIRS[@]}"
fi

# ── D. No flat handoff files at project memory root ───────────────────────
echo "## D. Migration completeness"
FLAT_CT=0
FLAT_FILES=()
if [ -d "$PROJECTS_DIR" ]; then
	while IFS= read -r f; do
		[ -z "$f" ] && continue
		FLAT_CT=$((FLAT_CT + 1))
		FLAT_FILES+=("$f")
	done < <(find "$PROJECTS_DIR" -maxdepth 3 -name 'handoff_*.md' -type f 2>/dev/null \
		| grep -v '/handoffs/' || true)
fi
if [ "$FLAT_CT" -eq 0 ]; then
	ok "D.1 no flat handoff_*.md outside handoffs/ subdirs"
else
	fail "D.1 flat handoff detection" "$FLAT_CT flat handoff(s) found, run migrate-memory.sh:"
	printf '          %s\n' "${FLAT_FILES[@]}"
fi

# ── E. load-global-memory hook emits on first call, silent on second ──────
echo "## E. load-global-memory hook"
TEST_SID="doctor-$$-$RANDOM"
MARKER="/tmp/claude-session-${TEST_SID}.global-loaded"
rm -f "$MARKER"
INPUT_E=$(jq -n --arg sid "$TEST_SID" --arg cwd "$PWD" \
	'{"session_id":$sid,"cwd":$cwd,"hook_event_name":"UserPromptSubmit","prompt":"x"}')
OUT1=$(printf '%s' "$INPUT_E" | bash "$LOAD_HOOK" 2>/dev/null || true)
OUT2=$(printf '%s' "$INPUT_E" | bash "$LOAD_HOOK" 2>/dev/null || true)
rm -f "$MARKER"

if [ -d "$GLOBAL_DIR" ] && [ -f "$GLOBAL_DIR/MEMORY.md" ]; then
	if printf '%s' "$OUT1" | grep -q '"systemMessage"'; then
		ok "E.1 first invocation emits systemMessage JSON"
	else
		fail "E.1 first invocation" "expected JSON with systemMessage, got: $(printf '%s' "$OUT1" | head -c 80)"
	fi
	if [ -z "$OUT2" ]; then
		ok "E.2 second invocation in same session emits nothing"
	else
		fail "E.2 second invocation" "expected empty output, got: $(printf '%s' "$OUT2" | head -c 80)"
	fi
else
	ok "E.* skipped (no global memory directory yet, run seed-memory.sh)"
fi

# ── F. pre-compact writes into handoffs/ subdir ───────────────────────────
echo "## F. pre-compact hook output path"
TEST_PROJ=$(mktemp -d)
TEST_SID_F="doctor-$$-$RANDOM-pc"
TEST_TR=$(mktemp)
echo '{}' >"$TEST_TR"
INPUT_F=$(printf '{"trigger":"manual","session_id":"%s","cwd":"%s","transcript_path":"%s"}' \
	"$TEST_SID_F" "$TEST_PROJ" "$TEST_TR")
PROJECT_KEY=$(echo "$TEST_PROJ" | tr '/.' '-')
EXPECTED_HANDOFFS_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory/handoffs"

printf '%s' "$INPUT_F" | bash "$PRE_HOOK" 2>/dev/null || true

WROTE_HANDOFF=$(find "$EXPECTED_HANDOFFS_DIR" -maxdepth 1 -name 'handoff_*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "${WROTE_HANDOFF:-0}" -ge 1 ]; then
	ok "F.1 pre-compact wrote handoff into handoffs/ subdir"
else
	fail "F.1 pre-compact subdir" "no handoff in $EXPECTED_HANDOFFS_DIR"
fi

# Cleanup synthetic project memory
rm -rf "$HOME/.claude/projects/$PROJECT_KEY"
rm -f "$TEST_TR"
rmdir "$TEST_PROJ" 2>/dev/null || true

# ── G. post-compact reads handoffs/ first ─────────────────────────────────
echo "## G. post-compact hook source"
TEST_PROJ_G=$(mktemp -d)
PROJECT_KEY_G=$(echo "$TEST_PROJ_G" | tr '/.' '-')
G_HANDOFFS="$HOME/.claude/projects/$PROJECT_KEY_G/memory/handoffs"
mkdir -p "$G_HANDOFFS"
echo "## SUBDIR_HANDOFF" >"$G_HANDOFFS/handoff_2026-04-29T00-00Z_aaaaa.md"

INPUT_G=$(printf '{"session_id":"doctor","cwd":"%s"}' "$TEST_PROJ_G")
OUT_G=$(printf '%s' "$INPUT_G" | bash "$POST_HOOK" 2>/dev/null || true)
if printf '%s' "$OUT_G" | grep -q 'SUBDIR_HANDOFF'; then
	ok "G.1 post-compact reads from handoffs/ subdir"
else
	fail "G.1 post-compact subdir read" "did not surface SUBDIR_HANDOFF marker"
fi

rm -rf "$HOME/.claude/projects/$PROJECT_KEY_G"
rmdir "$TEST_PROJ_G" 2>/dev/null || true

# ── Summary ──────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "memory-doctor: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
