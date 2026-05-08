#!/bin/bash
# pre-compact.sh, capture session state before context compaction
#
# Fires on both triggers:
#   trigger=manual , user ran /compact
#   trigger=auto   , context threshold hit automatically
#
# Writes a structured handoff file to the project memory directory's
# handoffs/ subdirectory. Filename uses ISO 8601 minute-precision UTC
# timestamps (handoff_2026-04-29T15-22Z_<sid>.md) so multiple compactions
# in the same day cannot collide on filename. Applies a rolling cap of
# 5 inside the handoffs/ subdir (oldest deleted on overflow).
#
# MEMORY.md is NOT mutated, handoffs are an opaque mechanism enforced
# by the subdirectory itself; the index stays focused on topical memory.
#
# Output file: ~/.claude/projects/<project>/memory/handoffs/handoff_<isots>_<id>.md
# Exit 0 always, never block compaction.

set -euo pipefail

# ── Parse hook input ──────────────────────────────────────────────────────────
INPUT=$(cat)

if ! command -v jq &>/dev/null; then
	echo "[pre-compact] jq not found, skipping handoff" >&2
	exit 0
fi

TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

if [ -z "$CWD" ]; then
	echo "[pre-compact] cwd missing from hook input, skipping" >&2
	exit 0
fi

# ── Derive paths ──────────────────────────────────────────────────────────────
# Claude Code sanitizes CWD to a project key by replacing / and . with -
PROJECT_KEY=$(echo "$CWD" | tr '/.' '-')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"
HANDOFFS_DIR="$MEMORY_DIR/handoffs"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Filename-safe ISO timestamp (no colons): 2026-04-29T15-22Z
FILE_TS=$(date -u +"%Y-%m-%dT%H-%MZ")
SESSION_SHORT="${SESSION_ID:0:8}"
HANDOFF_FILE="$HANDOFFS_DIR/handoff_${FILE_TS}_${SESSION_SHORT}.md"

mkdir -p "$HANDOFFS_DIR"

# ── Locate transcript JSONL ───────────────────────────────────────────────────
# Prefer transcript_path from hook input (provided by Claude Code directly)
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
	TRANSCRIPT="$TRANSCRIPT_PATH"
else
	# Fallback: derive from session ID, then most recent JSONL
	TRANSCRIPT="$HOME/.claude/projects/$PROJECT_KEY/${SESSION_ID}.jsonl"
	if [ ! -f "$TRANSCRIPT" ]; then
		TRANSCRIPT=$(ls -t "$HOME/.claude/projects/$PROJECT_KEY/"*.jsonl 2>/dev/null | head -1 || echo "")
	fi
fi

# ── Extract file activity from transcript ─────────────────────────────────────
FILE_READS=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
	FILE_READS=$(jq -r '
        # Assistant messages contain tool_use blocks
        select(.type == "assistant") |
        (.message.content // .content // [])[] |
        select(.type == "tool_use") |
        select(.name | test("^(Read|Write|Edit)$")) |
        "\(.name): \(.input.file_path // .input.path // "")"
    ' "$TRANSCRIPT" 2>/dev/null \
		| grep -v ': $' \
		| sort -u \
		| head -60 \
		|| echo "")
fi

if [ -z "$FILE_READS" ]; then
	FILE_READS="(no file reads detected in transcript)"
fi

# ── Git state ─────────────────────────────────────────────────────────────────
BRANCH="(not a git repo)"
GIT_STATUS="(not a git repo)"
RECENT_COMMITS="(not a git repo)"
CHANGED_FILES="(no changes)"

if git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
	BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "detached HEAD")
	GIT_STATUS=$(git -C "$CWD" status --short 2>/dev/null || echo "")
	RECENT_COMMITS=$(git -C "$CWD" log --oneline -5 2>/dev/null || echo "(no commits)")
	CHANGED_FILES=$(git -C "$CWD" diff --stat HEAD 2>/dev/null || echo "(no staged changes)")
	[ -z "$GIT_STATUS" ] && GIT_STATUS="(clean)"
	[ -z "$CHANGED_FILES" ] && CHANGED_FILES="(no staged changes)"
fi

# ── Write handoff file ────────────────────────────────────────────────────────
cat >"$HANDOFF_FILE" <<HANDOFF
---
name: Session handoff ${FILE_TS}
description: Pre-compact snapshot, ${TRIGGER} trigger, branch ${BRANCH}
type: project
---

**Trigger:** ${TRIGGER}
**Session:** ${SESSION_ID}
**Branch:** ${BRANCH}
**Project:** ${CWD}
**Timestamp:** ${TIMESTAMP}

## Files active this session

Do not re-read these files, their content was in context before compaction:

\`\`\`
${FILE_READS}
\`\`\`

## Git state

\`\`\`
${GIT_STATUS}
\`\`\`

## Recent commits

\`\`\`
${RECENT_COMMITS}
\`\`\`

## Files changed (git diff)

\`\`\`
${CHANGED_FILES}
\`\`\`
HANDOFF

# ── Apply rolling cap of 5 inside handoffs/ ───────────────────────────────────
# Keep newest 5 by mtime; delete the rest. The subdirectory itself is the
# bounded log; MEMORY.md is no longer touched.
CAP=5
COUNT=$(find "$HANDOFFS_DIR" -maxdepth 1 -name 'handoff_*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "${COUNT:-0}" -gt "$CAP" ]; then
	OVERFLOW=$((COUNT - CAP))
	# ls -1t lists newest first; tail -$OVERFLOW gives us the oldest to delete.
	ls -1t "$HANDOFFS_DIR"/handoff_*.md 2>/dev/null | tail -n "$OVERFLOW" | while IFS= read -r old; do
		rm -f "$old"
	done
fi

# Migration: if any flat handoff_*.md files still live in $MEMORY_DIR (from
# the pre-Phase-9 layout), move them into handoffs/ now. Idempotent.
for legacy in "$MEMORY_DIR"/handoff_*.md; do
	[ -f "$legacy" ] || continue
	mv "$legacy" "$HANDOFFS_DIR/"
done

echo "[pre-compact] handoff written: $HANDOFF_FILE" >&2
exit 0
