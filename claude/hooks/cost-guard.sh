#!/usr/bin/env bash
# cost-guard.sh, PreToolUse cost transparency hook
#
# Shows estimated token cost before expensive operations.
# Soft-gates general-purpose agent spawns (Claude pauses for user confirmation).
# Informs silently for Explore/Plan agents and WebFetch.
#
# Exit codes:
#   0 = allow, proceed (with optional info message)
#   1 = soft gate: show message to Claude, Claude pauses and surfaces to user
#
# Token cost reference (rough estimates):
#   Bash/Read/Grep/Glob/Edit/Write = 0 tokens (local operations, no API call)
#   WebFetch                       = ~1k-8k tokens (small summarization model)
#   Agent (Explore/Plan)           = ~2k-25k tokens (bounded research task)
#   Agent (general-purpose)        = ~10k-100k tokens (open-ended, unbounded)

if ! command -v jq &>/dev/null; then
	echo "[cost-guard] jq not found -- all agent spawns ungated. Install: brew install jq" >&2
	exit 0
fi

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' 2>/dev/null <<<"$INPUT")

case "$TOOL" in

	Agent)
		SUBTYPE=$(jq -r '.tool_input.subagent_type // "general-purpose"' 2>/dev/null <<<"$INPUT")
		DESC=$(jq -r '.tool_input.description // "no description"' 2>/dev/null <<<"$INPUT")
		PROMPT=$(jq -r '.tool_input.prompt // ""' 2>/dev/null <<<"$INPUT")
		CHARS=${#PROMPT}

		case "$SUBTYPE" in
			Explore | Plan | claude-code-guide)
				# Bounded research agents, inform but don't gate
				if [ "$CHARS" -gt 3000 ]; then
					RANGE="10k-30k tokens"
				elif [ "$CHARS" -gt 1000 ]; then
					RANGE="4k-15k tokens"
				else
					RANGE="2k-8k tokens"
				fi
				echo "[cost] $SUBTYPE agent (~$RANGE), $DESC" >&2
				exit 0
				;;
			*)
				# CodeRabbit surgeon spawns: bounded, Sonnet, surgical edits only, pass through
				if echo "$DESC" | grep -qE '^Fix CR-[0-9]+'; then
					echo "[cost] code-surgeon (~2k-8k tokens, Sonnet), $DESC" >&2
					exit 0
				fi
				# General-purpose agents are unbounded, gate these
				if [ "$CHARS" -gt 3000 ]; then
					TIER="VERY HIGH"
					RANGE="50k-150k tokens"
				elif [ "$CHARS" -gt 1000 ]; then
					TIER="HIGH"
					RANGE="15k-80k tokens"
				else
					TIER="MEDIUM"
					RANGE="5k-25k tokens"
				fi
				echo "[COST GATE] General-purpose agent, estimated $TIER ($RANGE)" >&2
				echo "Task: $DESC" >&2
				echo "Pause and confirm with the user before proceeding." >&2
				exit 1
				;;
		esac
		;;

	WebFetch)
		URL=$(jq -r '.tool_input.url // ""' 2>/dev/null <<<"$INPUT")
		echo "[cost] WebFetch (~1k-8k tokens), $URL" >&2
		exit 0
		;;

	*)
		exit 0
		;;

esac
