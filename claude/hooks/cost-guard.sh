#!/usr/bin/env bash
# cost-guard.sh, PreToolUse cost transparency hook
#
# Informs on agent and WebFetch cost; hard-gates general-purpose agent spawns
# above a per-session count threshold so a runaway session is mechanically stopped.
# Explore/Plan/code-surgeon spawns remain ungated.
#
# Exit codes:
#   0 = allow, proceed (with optional info message)
#   2 = hard block: tool call rejected; Claude must surface and re-decide
#
# Per-session GP cap:
#   COST_GUARD_GP_LIMIT (env var, default 5) caps general-purpose Agent spawns per session_id.
#   Counter stamp file: /tmp/claude-session-<session_id>.gp-count

if ! command -v jq &>/dev/null; then
	echo "[cost-guard] jq not found, all agent spawns ungated. Install: brew install jq" >&2
	exit 0
fi

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' 2>/dev/null <<<"$INPUT")
SESSION_ID=$(jq -r '.session_id // empty' 2>/dev/null <<<"$INPUT")
GP_LIMIT="${COST_GUARD_GP_LIMIT:-5}"

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
				# General-purpose agents are unbounded, count and gate above cap
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

				if [ -z "$SESSION_ID" ]; then
					# Without a session id, cannot count; inform and pass through
					echo "[cost] general-purpose agent, $TIER ($RANGE), $DESC (no session_id; uncounted)" >&2
					exit 0
				fi

				STAMP="/tmp/claude-session-${SESSION_ID}.gp-count"
				COUNT=0
				if [ -f "$STAMP" ]; then
					COUNT=$(cat "$STAMP" 2>/dev/null || echo 0)
					[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0
				fi
				NEW=$((COUNT + 1))

				if [ "$NEW" -gt "$GP_LIMIT" ]; then
					LOG_DIR="$HOME/.claude/logs"
					mkdir -p "$LOG_DIR" 2>/dev/null
					printf '%s\t%s\t%s\t%s\n' \
						"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION_ID" "$NEW" "$DESC" \
						>>"$LOG_DIR/cost-guard-blocks.log" 2>/dev/null || true
					echo "[COST GATE BLOCK] General-purpose agent #$NEW exceeds session cap ($GP_LIMIT)." >&2
					echo "Estimated $TIER ($RANGE). Task: $DESC" >&2
					echo "Surface to the user and ask whether to raise COST_GUARD_GP_LIMIT or invoke explicitly." >&2
					exit 2
				fi

				echo "$NEW" >"$STAMP"
				echo "[cost] general-purpose agent #$NEW/$GP_LIMIT, $TIER ($RANGE), $DESC" >&2
				exit 0
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
