#!/usr/bin/env bash
# session-start-context.sh, deliver memory context to the model via the
# SessionStart hook's additionalContext channel. systemMessage is
# display-only and never reaches Claude; this replaces the three hooks that
# relied on it (load-global-memory.sh, memory-quality-check.sh,
# post-compact.sh), see tmp/memory-system-review-2026-07-15.md gap G1.
#
# Fires on SessionStart sources:
#   startup/clear -> global memory payload + missing-project-memory advisory
#                    + monthly staleness advisory (stamp advances only when
#                    an advisory was actually emitted, not on every check)
#   compact       -> global memory payload + newest project handoff restore
#   resume        -> no injection; the payload already lives in the
#                    transcript being resumed, re-injecting would duplicate it
#
# Output: JSON { "hookSpecificOutput": { "hookEventName": "SessionStart",
#   "additionalContext": "..." }, "systemMessage": "one-line confirmation" }
# Exit 0 always, never blocks session start.

set -eu

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0

[ "$SOURCE" = "resume" ] && exit 0

GLOBAL_DIR="$HOME/.claude/memory"
INDEX="$GLOBAL_DIR/MEMORY.md"

GLOBAL_PAYLOAD=""
FILE_COUNT=0

if [ -f "$INDEX" ]; then
	GLOBAL_PAYLOAD="## Global memory (cross-project, user-level)

Restored once per session start from \`~/.claude/memory/\`. These are user-level facts and preferences that apply across every project on this machine.

### Index

$(cat "$INDEX")
"
	FILE_COUNT=$((FILE_COUNT + 1))

	while IFS= read -r f; do
		target="$GLOBAL_DIR/$f"
		# Guard against path traversal: target must resolve under GLOBAL_DIR.
		case "$target" in "$GLOBAL_DIR/"*) ;; *) continue ;; esac
		if [ -f "$target" ] && [ "$f" != "MEMORY.md" ]; then
			GLOBAL_PAYLOAD="$GLOBAL_PAYLOAD
### $f

$(cat "$target")
"
			FILE_COUNT=$((FILE_COUNT + 1))
		fi
		# Link regex includes '-' (G10 fix): filenames like some-fact.md were
		# previously indexed but silently excluded from injection.
	done < <(grep -oE '\([a-zA-Z0-9_.-]+\.md\)' "$INDEX" | tr -d '()' | sort -u)
fi

EXTRA_PAYLOAD=""

case "$SOURCE" in
	compact)
		if [ -n "$CWD" ]; then
			PROJECT_KEY=$(printf '%s' "$CWD" | tr '/.' '-')
			HANDOFFS_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory/handoffs"
			LATEST_HANDOFF=$(find "$HANDOFFS_DIR" -maxdepth 1 -name 'handoff_*.md' -type f 2>/dev/null | sort -r | head -1 || echo "")
			if [ -n "$LATEST_HANDOFF" ] && [ -f "$LATEST_HANDOFF" ]; then
				EXTRA_PAYLOAD="## Restored from pre-compact handoff

The following context was captured immediately before compaction. Use it to avoid re-reading files and to restore task continuity.

$(cat "$LATEST_HANDOFF")
"
			fi
		fi
		;;
	startup | clear)
		if [ -n "$CWD" ]; then
			PROJECT_KEY=$(printf '%s' "$CWD" | tr '/.' '-')
			PROJECT_INDEX="$HOME/.claude/projects/$PROJECT_KEY/memory/MEMORY.md"
			if [ ! -f "$PROJECT_INDEX" ]; then
				EXTRA_PAYLOAD="${EXTRA_PAYLOAD}
## Project memory not initialized

This project has no memory directory yet. Run \`/seed-project\` to bootstrap the project memory index and current-phase file.
"
			fi
		fi

		if [ -d "$GLOBAL_DIR" ]; then
			STATE_DIR="$HOME/.claude"
			STAMP="$STATE_DIR/.maintenance-memory-quality"
			TODAY=$(date +%Y-%m-%d)

			ymd_to_epoch() {
				if [[ "$OSTYPE" == darwin* ]]; then
					date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" +%s 2>/dev/null || echo 0
				else
					date -d "$1 00:00:00" +%s 2>/dev/null || echo 0
				fi
			}

			TODAY_SEC=$(ymd_to_epoch "$TODAY")
			LAST=$(cat "$STAMP" 2>/dev/null || echo "1970-01-01")
			LAST_SEC=$(ymd_to_epoch "$LAST")
			DAYS_SINCE=$(((TODAY_SEC - LAST_SEC) / 86400))

			if [ "$DAYS_SINCE" -ge 30 ]; then
				STALE=""
				NOW_SEC=$(date +%s)

				while IFS= read -r f; do
					base=$(basename "$f")
					[ "$base" = "MEMORY.md" ] && continue

					# Prefer git history over mtime: git pull/checkout rewrites mtimes on a
					# synced machine, which would otherwise under-report staleness.
					git_ts=$(git -C "$GLOBAL_DIR" log -1 --format=%ct -- "$base" 2>/dev/null || echo "")
					if [ -n "$git_ts" ]; then
						age_days=$(((NOW_SEC - git_ts) / 86400))
					else
						if [[ "$OSTYPE" == darwin* ]]; then
							mtime=$(stat -f %m "$f" 2>/dev/null || echo 0)
						else
							mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
						fi
						age_days=$(((NOW_SEC - mtime) / 86400))
					fi

					if [ "$age_days" -gt 90 ]; then
						STALE="${STALE}- \`${base}\` (${age_days} days since last change)
"
					fi
				done < <(
					for candidate in "$GLOBAL_DIR"/*.md; do
						[ -f "$candidate" ] && printf '%s\n' "$candidate"
					done | sort
				)

				if [ -n "$STALE" ]; then
					EXTRA_PAYLOAD="${EXTRA_PAYLOAD}
## Memory quality advisory (monthly)

The following global memory files have not changed in over 90 days. During this session, evaluate whether each still reflects how the user works. Surface any that seem stale, inaccurate, or no longer applicable -- with a one-sentence summary of the concern -- and ask the user whether to update or remove it. Only raise this if you have a genuine signal; do not mention it if the content still looks current.

${STALE}"
					# Delivery-gated (G2 fix): only advance the stamp when an advisory was
					# actually emitted. Advancing unconditionally silently skips a month's
					# check with nothing to show for it.
					echo "$TODAY" >"$STAMP"
				fi
			fi
		fi
		;;
esac

FULL_PAYLOAD="${GLOBAL_PAYLOAD}${EXTRA_PAYLOAD}"

[ -n "$FULL_PAYLOAD" ] || exit 0

BYTES=$(printf '%s' "$GLOBAL_PAYLOAD" | wc -c | tr -d ' ')
TOKENS=$((BYTES * 10 / 35))
CONFIRM="global memory loaded: ${FILE_COUNT} file(s), ~${TOKENS} tok"

jq -n --arg ctx "$FULL_PAYLOAD" --arg msg "$CONFIRM" \
	'{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}, "systemMessage": $msg}'

exit 0
