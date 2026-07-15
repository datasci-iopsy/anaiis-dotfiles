#!/usr/bin/env bash
# memory-doctor.sh, verify the memory pipeline end to end.
#
# Reports per-project memory health and synthetically exercises
# session-start-context.sh and pre-compact.sh so problems surface without
# waiting for a real session or compaction.
#
# Exits 0 if all checks pass, 1 otherwise. Output is structured so the
# script is grep-able from a higher-level test or schedule.
#
# Checks:
#   A. Global tier is a symlink resolving into the dotfiles repo, and indexed.
#   B. Each topical file has valid frontmatter (name, description, and a
#      type field either top-level or nested under metadata:).
#   C. Each project memory dir has a handoffs/ subdir; bounded ≤5.
#   D. No flat handoff_*.md sitting at project memory root (migration done).
#   E. session-start-context hook emits hookSpecificOutput.additionalContext
#      (the channel that reaches the model; systemMessage alone does not).
#   F. pre-compact hook places handoff in handoffs/ subdir when invoked synthetically.
#   G. session-start-context hook (source=compact) restores from handoffs/ first.
#   H. receipt: the newest real transcript for this project carries the global
#      memory payload as delivered context, not merely a tool_result blob.
#      SKIPs (not PASS) when no post-fix transcript exists yet.
#   I. No file basename exists in both the global tier and any project tier
#      (cross-tier duplicates drift independently once they exist).
#   J. Index<->file consistency: every global memory file is linked from
#      MEMORY.md, and every link in MEMORY.md resolves to an existing file.
#   K. Every global memory filename matches the index-link regex the
#      session-start-context hook uses to extract linked files.
#   L. Global tier injected payload stays within a 2,000-token budget.
#   M. No project-tier memory dir still holds an unmigrated user_*.md file.
#
# Usage: bash ~/.claude/scripts/memory-doctor.sh

set -u

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"
PROJECTS_DIR="$HOME/.claude/projects"
GLOBAL_DIR="$HOME/.claude/memory"
INDEX="$GLOBAL_DIR/MEMORY.md"
SESSION_START_HOOK="$REPO_DIR/claude/hooks/session-start-context.sh"
PRE_HOOK="$REPO_DIR/claude/hooks/pre-compact.sh"

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
if [ -L "$GLOBAL_DIR" ] && [ "$(cd "$GLOBAL_DIR" 2>/dev/null && pwd -P)" = "$REPO_DIR/claude/memory" ]; then
	ok "A.1 global memory is a symlink into the dotfiles repo"
elif [ -d "$GLOBAL_DIR" ]; then
	fail "A.1 global memory is a symlink into the dotfiles repo" \
		"real directory at $GLOBAL_DIR; merge its contents into claude/memory/ and replace with: ln -sfn $REPO_DIR/claude/memory $GLOBAL_DIR"
else
	fail "A.1 global memory is a symlink into the dotfiles repo" "missing: $GLOBAL_DIR (run install.sh)"
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
	local head10
	head10=$(head -10 "$f")
	if ! (printf '%s\n' "$head10" | grep -q '^name:' \
		&& printf '%s\n' "$head10" | grep -q '^description:' \
		&& printf '%s\n' "$head10" | grep -qE '^(type:|[[:space:]]+type:)'); then
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
	fail "D.1 flat handoff detection" "$FLAT_CT flat handoff(s) found, run migrate-memory.sh --apply:"
	printf '          %s\n' "${FLAT_FILES[@]}"
fi

# ── E. session-start-context hook delivers via additionalContext ──────────
echo "## E. session-start-context hook (additionalContext channel)"
TEST_SID="doctor-$$-$RANDOM"
INPUT_E=$(jq -n --arg sid "$TEST_SID" --arg cwd "$PWD" \
	'{"source":"startup","session_id":$sid,"cwd":$cwd,"hook_event_name":"SessionStart"}')
OUT1=$(printf '%s' "$INPUT_E" | bash "$SESSION_START_HOOK" 2>/dev/null || true)
INPUT_E_RESUME=$(jq -n --arg sid "$TEST_SID" --arg cwd "$PWD" \
	'{"source":"resume","session_id":$sid,"cwd":$cwd,"hook_event_name":"SessionStart"}')
OUT_RESUME=$(printf '%s' "$INPUT_E_RESUME" | bash "$SESSION_START_HOOK" 2>/dev/null || true)

if [ -d "$GLOBAL_DIR" ] && [ -f "$GLOBAL_DIR/MEMORY.md" ]; then
	CTX1=$(printf '%s' "$OUT1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
	EVT1=$(printf '%s' "$OUT1" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
	if [ -n "$CTX1" ]; then
		ok "E.1 startup source emits hookSpecificOutput.additionalContext"
	else
		fail "E.1 startup source" "expected non-empty hookSpecificOutput.additionalContext, got: $(printf '%s' "$OUT1" | head -c 80)"
	fi
	if [ "$EVT1" = "SessionStart" ]; then
		ok "E.2 hookEventName is SessionStart"
	else
		fail "E.2 hookEventName" "expected 'SessionStart', got: '$EVT1'"
	fi
	if [ -z "$OUT_RESUME" ]; then
		ok "E.3 resume source emits nothing (payload already in resumed transcript)"
	else
		fail "E.3 resume source" "expected empty output, got: $(printf '%s' "$OUT_RESUME" | head -c 80)"
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

# ── G. session-start-context (source=compact) restores from handoffs/ ─────
echo "## G. session-start-context hook, compact source"
TEST_PROJ_G=$(mktemp -d)
PROJECT_KEY_G=$(echo "$TEST_PROJ_G" | tr '/.' '-')
G_HANDOFFS="$HOME/.claude/projects/$PROJECT_KEY_G/memory/handoffs"
mkdir -p "$G_HANDOFFS"
echo "## SUBDIR_HANDOFF" >"$G_HANDOFFS/handoff_2026-04-29T00-00Z_aaaaa.md"

INPUT_G=$(printf '{"source":"compact","session_id":"doctor","cwd":"%s"}' "$TEST_PROJ_G")
OUT_G=$(printf '%s' "$INPUT_G" | bash "$SESSION_START_HOOK" 2>/dev/null || true)
CTX_G=$(printf '%s' "$OUT_G" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
if printf '%s' "$CTX_G" | grep -q 'SUBDIR_HANDOFF'; then
	ok "G.1 compact source restores from handoffs/ subdir"
else
	fail "G.1 compact source restore" "did not surface SUBDIR_HANDOFF marker"
fi

rm -rf "$HOME/.claude/projects/$PROJECT_KEY_G"
rmdir "$TEST_PROJ_G" 2>/dev/null || true

# ── H. receipt: some real transcript for this project carries the payload ──
echo "## H. receipt (live transcript)"
# CC 2.1.207 logs a SessionStart hook's additionalContext as a dedicated
# {"type":"attachment","attachment":{"type":"hook_additional_context",
# "hookEvent":"SessionStart", "content":[...]}} record, confirmed against a
# real headless (`claude -p`) transcript, never as a "user"-role message.
# That record type is emitted solely by the harness's own hook-delivery
# pipeline, so unlike a plain string match it cannot be produced by an
# assistant merely quoting the header text or by manually invoking the hook
# via Bash (both show up as "assistant" / tool_use|tool_result records
# instead).
#
# Scan every transcript, not just the newest by mtime: the currently active
# session's own file is always the most recently modified one while this
# doctor runs inside it, but that session may predate the current settings
# and, once resumed, its SessionStart events are all "resume" sources, which
# by design never re-emit the payload (see architecture decision 1). Picking
# by mtime alone would perpetually inspect a file structurally incapable of
# ever carrying fresh evidence. SKIPs rather than fails when no transcript
# carries the record yet.
CURRENT_KEY=$(echo "$REPO_DIR" | tr '/.' '-')
CURRENT_TRANSCRIPTS="${MEMORY_DOCTOR_TRANSCRIPTS_DIR:-$PROJECTS_DIR/$CURRENT_KEY}"

RECEIPT=""
if [ -d "$CURRENT_TRANSCRIPTS" ]; then
	for f in "$CURRENT_TRANSCRIPTS"/*.jsonl; do
		[ -f "$f" ] || continue
		HIT=$(jq -r 'select(.type == "attachment") |
			select(.attachment.type == "hook_additional_context" and .attachment.hookEvent == "SessionStart") |
			select(((.attachment.content // []) | join("\n")) | contains("## Global memory (cross-project")) |
			.timestamp' "$f" 2>/dev/null | tail -1)
		if [ -n "$HIT" ] && { [ -z "$RECEIPT" ] || [[ "$HIT" > "$RECEIPT" ]]; }; then
			RECEIPT="$HIT"
		fi
	done
fi

if [ -z "$RECEIPT" ]; then
	ok "H.1 skipped (no post-fix transcript carries the payload yet; expected until the next real session)"
else
	ok "H.1 a real transcript carries a genuine SessionStart additionalContext attachment (most recent: $RECEIPT)"
fi

# ── I. Cross-tier basename collision ───────────────────────────────────────
echo "## I. Cross-tier basename collision"
COLLISION_FILES=()
if [ -d "$PROJECTS_DIR" ] && [ -d "$GLOBAL_DIR" ]; then
	while IFS= read -r f; do
		base=$(basename "$f")
		[ "$base" = "MEMORY.md" ] && continue
		[ -f "$GLOBAL_DIR/$base" ] && COLLISION_FILES+=("$f (also in $GLOBAL_DIR/$base)")
	done < <(find "$PROJECTS_DIR" -mindepth 3 -maxdepth 3 -name '*.md' -type f 2>/dev/null)
fi
if [ "${#COLLISION_FILES[@]}" -eq 0 ]; then
	ok "I.1 no cross-tier basename collisions"
else
	fail "I.1 cross-tier collision" "${#COLLISION_FILES[@]} file(s) exist in both tiers under the same name:"
	printf '          %s\n' "${COLLISION_FILES[@]}"
fi

# ── J. Index<->file consistency ────────────────────────────────────────────
echo "## J. Index<->file consistency"
UNLINKED=()
if [ -d "$GLOBAL_DIR" ] && [ -f "$INDEX" ]; then
	for f in "$GLOBAL_DIR"/*.md; do
		[ -f "$f" ] || continue
		base=$(basename "$f")
		[ "$base" = "MEMORY.md" ] && continue
		grep -qF "($base)" "$INDEX" || UNLINKED+=("$base")
	done
fi
if [ "${#UNLINKED[@]}" -eq 0 ]; then
	ok "J.1 every global memory file is linked from the index"
else
	fail "J.1 unlinked files" "${#UNLINKED[@]} file(s) exist but are not linked from MEMORY.md:"
	printf '          %s\n' "${UNLINKED[@]}"
fi

DEAD_LINKS=()
if [ -f "$INDEX" ]; then
	while IFS= read -r target; do
		[ "$target" = "MEMORY.md" ] && continue
		[ -f "$GLOBAL_DIR/$target" ] || DEAD_LINKS+=("$target")
	done < <(grep -oE '\([a-zA-Z0-9_.-]+\.md\)' "$INDEX" 2>/dev/null | tr -d '()' | sort -u)
fi
if [ "${#DEAD_LINKS[@]}" -eq 0 ]; then
	ok "J.2 every indexed link resolves to an existing file"
else
	fail "J.2 dead links" "${#DEAD_LINKS[@]} link(s) point at missing files:"
	printf '          %s\n' "${DEAD_LINKS[@]}"
fi

# ── K. Filename lint (index-link regex compatibility) ─────────────────────
echo "## K. Filename lint"
BAD_NAMES=()
if [ -d "$GLOBAL_DIR" ]; then
	for f in "$GLOBAL_DIR"/*.md; do
		[ -f "$f" ] || continue
		base=$(basename "$f")
		[ "$base" = "MEMORY.md" ] && continue
		printf '%s' "$base" | grep -qE '^[a-zA-Z0-9_.-]+\.md$' || BAD_NAMES+=("$base")
	done
fi
if [ "${#BAD_NAMES[@]}" -eq 0 ]; then
	ok "K.1 all global memory filenames match the index-link regex"
else
	fail "K.1 filename lint" "${#BAD_NAMES[@]} filename(s) the link regex cannot match:"
	printf '          %s\n' "${BAD_NAMES[@]}"
fi

# ── L. Payload budget ───────────────────────────────────────────────────────
echo "## L. Payload budget"
if [ -f "$INDEX" ]; then
	TOTAL_BYTES=$(wc -c <"$INDEX" | tr -d ' ')
	while IFS= read -r f; do
		target="$GLOBAL_DIR/$f"
		[ -f "$target" ] && [ "$f" != "MEMORY.md" ] || continue
		sz=$(wc -c <"$target" | tr -d ' ')
		TOTAL_BYTES=$((TOTAL_BYTES + sz))
	done < <(grep -oE '\([a-zA-Z0-9_.-]+\.md\)' "$INDEX" 2>/dev/null | tr -d '()' | sort -u)
	TOTAL_TOKENS=$((TOTAL_BYTES * 10 / 35))
	if [ "$TOTAL_TOKENS" -le 2000 ]; then
		ok "L.1 global payload within 2k token budget (~${TOTAL_TOKENS} tok)"
	else
		fail "L.1 payload budget" "global payload ~${TOTAL_TOKENS} tok exceeds the 2k budget"
	fi
else
	ok "L.1 skipped (no global index)"
fi

# ── M. Pending migration ────────────────────────────────────────────────────
echo "## M. Pending migration"
PENDING=()
if [ -d "$PROJECTS_DIR" ]; then
	while IFS= read -r f; do
		case "$(basename "$f")" in
			user_*.md) PENDING+=("$f") ;;
		esac
	done < <(find "$PROJECTS_DIR" -mindepth 3 -maxdepth 3 -name '*.md' -type f 2>/dev/null)
fi
if [ "${#PENDING[@]}" -eq 0 ]; then
	ok "M.1 no project-tier dirs holding unmigrated user-level files"
else
	fail "M.1 pending migration" "${#PENDING[@]} project-tier user_*.md file(s) need migrate-memory.sh --apply:"
	printf '          %s\n' "${PENDING[@]}"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "memory-doctor: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
