#!/usr/bin/env bash
# ~/.claude/scripts/statusline-command.sh
#
# Claude Code rich status line, pure bash + jq, zero extra deps.
# Receives Claude session JSON on stdin; prints up to 3 colored lines.
# Designed for dark-mode terminals. Compatible with macOS and Linux (Ubuntu/RHEL).
#
# Line 1, identity:   model · effort · [vim] · ⎇ branch +staged ~modified
# Line 2, session:    context:[bar]% · in:X · out:X · cache · $session
# Line 3, billing:    5h:[bar]% reset · 7d% · repo:$X · all:$X
#
# Costs beyond the live session are read from ~/.claude/projects/<slug>/*.jsonl
# and cached for 5 minutes to avoid re-scanning on every refresh.
#
# Fields not yet in the Claude JSON payload (upstream feature requests):
#   - effort level  → read from ~/.claude/settings.json (updates on /effort)
#   - memory usage  → not exposed by Claude Code

command -v jq &>/dev/null || exit 0

input=$(cat)
printf '%s\n' "$input" | jq -e . &>/dev/null || exit 0

# ─── Locale: Unicode vs ASCII fallback ───────────────────────────────────────
if [[ "${LANG:-}${LC_ALL:-}${LC_CTYPE:-}" == *UTF-8* ]]; then
	BAR_F="█"
	BAR_E="░"
	WT_ICON="⎇ "
	CENT="¢"
else
	BAR_F="#"
	BAR_E="-"
	WT_ICON="wt:"
	CENT="c"
fi

# ─── ANSI, bright palette for dark-mode terminals ───────────────────────────
rs=$'\033[0m'
dim=$'\033[2m'
bd=$'\033[1m'

b_cyn=$'\033[96m' # model
b_grn=$'\033[92m' # low usage / clean
b_yel=$'\033[93m' # medium / cost
b_mag=$'\033[95m' # rate limits / worktree
b_blu=$'\033[94m' # git / cache
b_red=$'\033[91m' # high usage / warn
b_wht=$'\033[97m' # misc / cost labels

SEP="${dim}·${rs}"

# ─── Parse Claude JSON in a single jq pass ───────────────────────────────────
_jq=$(printf '%s\n' "$input" | jq -r '
    "model_raw=\(.model.id // "" | @sh)",
    "cwd_j=\(.workspace.current_dir // .cwd // "" | @sh)",
    "ctx_pct=\(.context_window.used_percentage // 0 | floor)",
    "in_tok=\(.context_window.current_usage.input_tokens // 0)",
    "out_tok=\(.context_window.current_usage.output_tokens // 0)",
    "cache_r=\(.context_window.current_usage.cache_read_input_tokens // 0)",
    "five_pct=\(.rate_limits.five_hour.used_percentage // 0 | floor)",
    "five_resets=\(.rate_limits.five_hour.resets_at // 0)",
    "week_pct=\(.rate_limits.seven_day.used_percentage // 0 | floor)",
    "cost_usd=\(.cost.total_cost_usd // 0)",
    "vim_mode=\(.vim.mode // "" | @sh)",
    "wt_name=\(.workspace.git_worktree // .worktree.name // "" | @sh)"
' 2>/dev/null)
[ -z "$_jq" ] && exit 0
eval "$_jq" 2>/dev/null || exit 0

cwd="${cwd_j:-$PWD}"

# Effort level: settings.json is rewritten immediately on /effort, so this
# always reflects the current level without needing a JSON payload change.
effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)

# ─── Helpers ─────────────────────────────────────────────────────────────────

shorten_model() {
	local s="${1#claude-}"
	s=$(printf '%s' "$s" | sed 's/-[0-9]\{8\}$//')
	s=$(printf '%s' "$s" | sed 's/-\([0-9][0-9]*\)$/.\1/')
	printf '%s' "$s"
}

# Tokens: < 1000 → raw ("400"), >= 1000 → one decimal if meaningful ("1.5k", "6k")
fmt_k() {
	local n=${1:-0}
	if [ "$n" -ge 1000 ] 2>/dev/null; then
		local whole=$((n / 1000))
		local frac=$(((n % 1000) / 100))
		[ "$frac" -gt 0 ] && printf '%d.%dk' "$whole" "$frac" || printf '%dk' "$whole"
	else
		printf '%d' "$n"
	fi
}

# Dollars: <$0.01 → "<1¢",  <$10 → "$2.47",  <$1000 → "$312",  else → "$1.2k"
fmt_cost() {
	awk -v c="${1:-0}" -v cent="$CENT" 'BEGIN {
        v = c + 0
        if      (v <= 0)    { exit }
        else if (v < 0.01)  { printf "<1%s",    cent }
        else if (v < 10)    { printf "$%.2f",   v    }
        else if (v < 1000)  { printf "$%.0f",   v    }
        else                { printf "$%.1fk",  v/1000 }
    }' 2>/dev/null
}

# Colored progress bar: fill chars colored by urgency, empty chars dimmed
progress_bar() {
	local pct=$1 width=${2:-8}
	local filled=$((pct * width / 100))
	[ "$filled" -gt "$width" ] && filled=$width
	local empty=$((width - filled))
	local fill_col bar="" i
	if [ "$pct" -ge 80 ]; then
		fill_col="${b_red}${bd}"
	elif [ "$pct" -ge 60 ]; then
		fill_col="${b_yel}"
	else
		fill_col="${b_grn}"
	fi
	for ((i = 0; i < filled; i++)); do bar+="${fill_col}${BAR_F}${rs}"; done
	for ((i = 0; i < empty; i++)); do bar+="${dim}${BAR_E}${rs}"; done
	printf '%s' "$bar"
}

pct_color() {
	if [ "${1:-0}" -ge 80 ] 2>/dev/null; then
		printf '%s' "${b_red}${bd}"
	elif [ "${1:-0}" -ge 60 ] 2>/dev/null; then
		printf '%s' "${b_yel}"
	else
		printf '%s' "${b_grn}"
	fi
}

# Cross-platform file modification time (seconds since epoch)
file_mtime() {
	stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# ─── Repo + total costs (JSONL aggregation with 5-minute cache) ───────────────
# Claude stores per-session JSONL files under ~/.claude/projects/<slug>/.
# On Max/Pro subscriptions costUSD is null, so cost is computed from token counts
# using current Anthropic list pricing per model family.
# Results are cached for 5 minutes to avoid re-scanning on every refresh.

CACHE_TTL=300 # seconds (5 minutes)
_uid=$(id -u 2>/dev/null || echo "0")
CACHE_BASE="/tmp/claude-sl-${_uid}"

# Convert cwd path to Claude project slug
# Encoding: replace /. with -- first, then / with -
_slug=$(printf '%s' "$cwd" | sed 's|/\.|--|g; s|/|-|g')

REPO_CACHE="${CACHE_BASE}-repo-costs.txt"
ALL_CACHE="${CACHE_BASE}-all-costs.txt"
SLUG_FILE="${CACHE_BASE}-slug.txt"

_now=$(date +%s 2>/dev/null || echo 0)

# jq function: compute USD cost from token counts by model family.
# Pricing per million tokens (list prices as of mid-2025):
#   opus:   $15 in / $75 out / $18.75 cache-write / $1.50 cache-read
#   sonnet: $3  in / $15 out / $3.75  cache-write / $0.30 cache-read
#   haiku:  $0.80 in / $4 out / $1.00 cache-write / $0.08 cache-read
_COST_JQ='
def mcost(m; u):
    ( if   (m | test("opus"))  then {i:15,   o:75,  cw:18.75, cr:1.50}
      elif (m | test("haiku")) then {i:0.80, o:4,   cw:1.00,  cr:0.08}
      else                          {i:3,    o:15,  cw:3.75,  cr:0.30}
      end ) as $p |
    ( ((u.input_tokens                // 0) * $p.i  +
       (u.output_tokens               // 0) * $p.o  +
       (u.cache_creation_input_tokens // 0) * $p.cw +
       (u.cache_read_input_tokens     // 0) * $p.cr ) / 1000000 );

[ .[] |
    select(.type == "assistant" and (.isSnapshotUpdate != true)) |
    mcost( (.message.model // "claude-sonnet"); (.message.usage // {}) )
] | add // 0
'

# Invalidate repo cache if the cwd (project) changed
if [ -f "$SLUG_FILE" ]; then
	_cached_slug=$(cat "$SLUG_FILE" 2>/dev/null)
	[ "$_cached_slug" != "$_slug" ] && rm -f "$REPO_CACHE" "$SLUG_FILE"
fi

# Repo cost
repo_cost=""
if [ -f "$REPO_CACHE" ] \
	&& [ $((_now - $(file_mtime "$REPO_CACHE"))) -lt $CACHE_TTL ] 2>/dev/null; then
	repo_cost=$(cat "$REPO_CACHE" 2>/dev/null)
else
	_proj_dir="$HOME/.claude/projects/$_slug"
	if [ -d "$_proj_dir" ]; then
		repo_cost=$(cat "$_proj_dir"/*.jsonl 2>/dev/null \
			| jq -rs "$_COST_JQ" 2>/dev/null)
		printf '%s' "${repo_cost:-0}" >"$REPO_CACHE"
		printf '%s' "$_slug" >"$SLUG_FILE"
	fi
fi

# Total cost across all projects
all_cost=""
if [ -f "$ALL_CACHE" ] \
	&& [ $((_now - $(file_mtime "$ALL_CACHE"))) -lt $CACHE_TTL ] 2>/dev/null; then
	all_cost=$(cat "$ALL_CACHE" 2>/dev/null)
else
	all_cost=$(cat "$HOME/.claude/projects"/*/*.jsonl 2>/dev/null \
		| jq -rs "$_COST_JQ" 2>/dev/null)
	printf '%s' "${all_cost:-0}" >"$ALL_CACHE"
fi

# ─── Build line arrays ────────────────────────────────────────────────────────
line1=() # identity: model · effort · vim · git
line2=() # session:  ctx · tok · cache · session cost
line3=() # billing:  5h bar · 7d · repo cost · all cost

# ── Line 1 ────────────────────────────────────────────────────────────────────

# Model
if [ -n "$model_raw" ]; then
	line1+=("$(printf "${b_cyn}${bd}%s${rs}" "$(shorten_model "$model_raw")")")
fi

# Effort
if [ -n "$effort" ]; then
	case "$effort" in
		low) line1+=("$(printf "${b_grn}${dim}↓low${rs}")") ;;
		medium) line1+=("$(printf "${b_yel}${dim}▶med${rs}")") ;;
		high) line1+=("$(printf "${b_red}${bd}↑high${rs}")") ;;
		*) line1+=("$(printf "${dim}%s${rs}" "$effort")") ;;
	esac
fi

# Vim mode
if [ -n "$vim_mode" ]; then
	line1+=("$(printf "${dim}[%s]${rs}" "$vim_mode")")
fi

# Directory: last two path components of cwd (e.g. "mattermoreai/dbt")
_d1=$(basename "$cwd")
_d2=$(basename "$(dirname "$cwd")")
if [ -n "$_d2" ] && [ "$_d2" != "." ] && [ "$_d2" != "/" ]; then
	dir_short="${_d2}/${_d1}"
else
	dir_short="$_d1"
fi
[ -n "$dir_short" ] && line1+=("$(printf "${dim}${b_wht}%s${rs}" "$dir_short")")

# Git: branch + worktree indicator + dirty counts
if command -v git &>/dev/null; then
	branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
	if [ -n "$branch" ]; then
		is_wt=false
		if [ -n "$wt_name" ]; then
			is_wt=true
		else
			_gd=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
			_gc=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
			[ -n "$_gd" ] && [ "$_gd" != "$_gc" ] && is_wt=true
		fi

		staged=0
		modified=0
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			x="${line:0:1}"
			y="${line:1:1}"
			[[ "$x" != " " && "$x" != "?" ]] && ((staged++))
			[[ "$y" != " " && "$y" != "?" ]] && ((modified++))
		done < <(git -C "$cwd" status --porcelain -uno 2>/dev/null)

		prefix=""
		[ "$is_wt" = "true" ] && prefix="${b_mag}${dim}${WT_ICON}${rs}"

		dirty=""
		[ "$staged" -gt 0 ] && dirty+=" ${b_grn}+${staged}${rs}"
		[ "$modified" -gt 0 ] && dirty+=" ${b_yel}~${modified}${rs}"

		line1+=("$(printf "${b_blu}%s${bd}%s${rs}%s" "$prefix" "$branch" "$dirty")")
	fi
fi

# ── Line 2 ────────────────────────────────────────────────────────────────────

# Context window %
if [ "${ctx_pct:-0}" -gt 0 ] 2>/dev/null; then
	col=$(pct_color "$ctx_pct")
	bar=$(progress_bar "$ctx_pct" 8)
	line2+=("$(printf "${col}context:[%s${col}]%d%%${rs}" "$bar" "$ctx_pct")")
fi

# Token counts
if [ "${in_tok:-0}" -gt 0 ] 2>/dev/null \
	&& [ "${out_tok:-0}" -gt 0 ] 2>/dev/null; then
	line2+=("$(printf "${dim}tok:${rs}${b_grn}${dim}%s${b_wht}${dim}+%s${rs}" \
		"$(fmt_k "$in_tok")" "$(fmt_k "$out_tok")")")
fi

# Cache reads
if [ "${cache_r:-0}" -ge 1000 ] 2>/dev/null; then
	line2+=("$(printf "${b_blu}${dim}cache:%s${rs}" "$(fmt_k "$cache_r")")")
fi

sess_str=$(fmt_cost "$cost_usd")

# ── Line 3 ────────────────────────────────────────────────────────────────────

# 5-hour block with colored bar + time until reset
if [ "${five_pct:-0}" -gt 0 ] 2>/dev/null; then
	bar=$(progress_bar "$five_pct" 8)
	col=$(pct_color "$five_pct")
	time_str=""
	if [ "${five_resets:-0}" -gt 0 ] && [ "$_now" -gt 0 ] 2>/dev/null; then
		remaining=$((five_resets - _now))
		if [ "$remaining" -gt 0 ]; then
			hrs=$((remaining / 3600))
			mins=$(((remaining % 3600) / 60))
			if [ "$hrs" -gt 0 ]; then
				time_str=" ${dim}${hrs}h${mins}m${rs}"
			else
				time_str=" ${dim}${mins}m${rs}"
			fi
		fi
	fi
	line3+=("$(printf "${col}5h:[%s${col}]%d%%%s${rs}" "$bar" "$five_pct" "$time_str")")
fi

# 7-day rate limit
if [ "${week_pct:-0}" -gt 0 ] 2>/dev/null; then
	col=$(pct_color "$week_pct")
	line3+=("$(printf "${col}${dim}7d:%d%%${rs}" "$week_pct")")
fi

# Session cost
if [ -n "$sess_str" ]; then
	line3+=("$(printf "${b_wht}${dim}sess:%s${rs}" "$sess_str")")
fi

# Repo cost (from JSONL cache)
repo_str=$(fmt_cost "${repo_cost:-0}")
if [ -n "$repo_str" ]; then
	line3+=("$(printf "${b_yel}${dim}repo:%s${rs}" "$repo_str")")
fi

# Total cost across all projects (from JSONL cache)
all_str=$(fmt_cost "${all_cost:-0}")
if [ -n "$all_str" ]; then
	line3+=("$(printf "${b_mag}${dim}all:%s${rs}" "$all_str")")
fi

# ─── Render, each non-empty line wrapped in dim brackets ────────────────────
render_line() {
	local -n _segs=$1
	[ "${#_segs[@]}" -eq 0 ] && return
	local out="" i
	for i in "${!_segs[@]}"; do
		[ "$i" -eq 0 ] && out="${_segs[$i]}" || out="${out} ${SEP} ${_segs[$i]}"
	done
	printf "${dim}[${rs}%s${dim}]${rs}\n" "$out"
}

render_line line1
render_line line2
render_line line3
