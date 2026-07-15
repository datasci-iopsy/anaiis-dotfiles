#!/usr/bin/env bash
# migrate-memory.sh, one-shot, idempotent migration to Phase-9 memory layout.
#
# Two transformations, applied per machine:
#
#   1. Global tier: move user-level memory files out of every project memory
#      dir into ~/.claude/memory/ so they live once instead of duplicating.
#      Heuristic: file basename matches user_*.md, feedback_jq_*.md,
#      feedback_memory_workflow*.md, or feedback_agent_token_cost*.md.
#      If a target already exists in the global tier, the newer-by-mtime
#      copy wins, UNLESS the candidate's content matches a known
#      memory-templates/ stub (current or retired), in which case it is
#      refused outright: a freshly seeded template file always has a newer
#      mtime than a curated real file, and would otherwise silently clobber
#      it (demonstrated in tmp/memory-system-review-2026-07-15.md gap G3).
#
#   2. Handoff subdirectory: any flat handoff_*.md files at the top level
#      of a project memory dir are moved into that project's handoffs/
#      subdirectory.
#
# Defaults to a dry run; pass --apply to actually write changes. --dry-run
# is accepted as an explicit synonym for the default.
#
# Idempotent: re-running is a no-op once both transformations have completed.
# Reports actions taken; non-zero exit means an unexpected error.
#
# Usage: bash ~/.claude/scripts/migrate-memory.sh [--apply|--dry-run]

set -euo pipefail

DRY_RUN=true
case "${1:-}" in
	--apply) DRY_RUN=false ;;
	--dry-run | "") DRY_RUN=true ;;
	*)
		echo "Unknown argument: ${1}" >&2
		echo "Usage: bash ~/.claude/scripts/migrate-memory.sh [--apply|--dry-run]" >&2
		exit 1
		;;
esac

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"
PROJECTS_DIR="$HOME/.claude/projects"
GLOBAL_DIR="$HOME/.claude/memory"
GLOBAL_TEMPLATES="$DOTFILES/claude/memory-templates/global"

# Heuristic for which memory files are user-level (live once globally).
USER_LEVEL_PATTERNS=(
	"user_*.md"
	"feedback_jq_*.md"
	"feedback_memory_workflow*.md"
	"feedback_agent_token_cost*.md"
)

is_user_level() {
	local fn="$1"
	local pat
	for pat in "${USER_LEVEL_PATTERNS[@]}"; do
		# shellcheck disable=SC2053
		if [[ "$fn" == $pat ]]; then return 0; fi
	done
	return 1
}

# Checksums (sha256) of known project-tier template stubs: current templates
# in claude/memory-templates/ plus the pre-slim stubs retired when the
# global-tier templates were removed from that directory. A candidate whose
# content matches any of these is unedited placeholder text, never a
# genuine, promotable user fact.
TEMPLATE_STUB_CHECKSUMS=(
	"ba82258e9dbd44315d830cd4e23a05824d8d29b855b1a0cabfecb61e8b9fb0e8" # retired user_profile.md stub
	"becdd14fc0cffced38f8e74a35630fe8ae7e2fc2b60ca406dda35cbb4eb43202" # retired feedback_environment.md stub
	"f2defe835860f0a65e7ae5b3b7aabb6f79705a8057bdf7747096836e14183d45" # retired feedback_plan_mode.md stub
	"be071686817f4953f4b8ce4e92bcec03ea609627c08aee267f51c814fee52187" # retired feedback_shell_config.md stub
	"72ce1dfd7c7109b80ba0917a88af92e92f2eb73c5770e69fc3598cfaa57a71d4" # retired reference_global_config.md stub
)

is_template_stub() {
	local f="$1"
	local sum
	sum=$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1)
	[ -n "$sum" ] || return 1
	local known
	for known in "${TEMPLATE_STUB_CHECKSUMS[@]}"; do
		[ "$sum" = "$known" ] && return 0
	done
	if [ -d "$DOTFILES/claude/memory-templates" ]; then
		local tmpl
		for tmpl in "$DOTFILES/claude/memory-templates"/*.md; do
			[ -f "$tmpl" ] || continue
			[ "$sum" = "$(shasum -a 256 "$tmpl" 2>/dev/null | cut -d' ' -f1)" ] && return 0
		done
	fi
	return 1
}

action() {
	if $DRY_RUN; then
		echo "  WOULD: $*"
	else
		echo "  $*"
	fi
}

# ── 1. Bootstrap global tier from templates if absent ─────────────────────
if [ ! -d "$GLOBAL_DIR" ]; then
	action "create $GLOBAL_DIR (from templates)"
	if ! $DRY_RUN; then
		mkdir -p "$GLOBAL_DIR"
		if [ -d "$GLOBAL_TEMPLATES" ]; then
			cp "$GLOBAL_TEMPLATES"/*.md "$GLOBAL_DIR/" 2>/dev/null || true
		fi
	fi
fi

# ── 2. Promote user-level files from each project memory dir ──────────────
PROMOTED=0
SKIPPED=0
REFUSED=0
[ -d "$PROJECTS_DIR" ] || { echo "No projects dir at $PROJECTS_DIR; skipping promotion."; }

if [ -d "$PROJECTS_DIR" ]; then
	for proj in "$PROJECTS_DIR"/*/memory; do
		[ -d "$proj" ] || continue
		for f in "$proj"/*.md; do
			[ -f "$f" ] || continue
			fn="$(basename "$f")"
			[ "$fn" = "MEMORY.md" ] && continue
			is_user_level "$fn" || continue

			if is_template_stub "$f"; then
				action "refuse (unedited template stub) $f"
				REFUSED=$((REFUSED + 1))
				continue
			fi

			target="$GLOBAL_DIR/$fn"
			if [ -f "$target" ]; then
				# Conflict: keep newer by mtime.
				if [ "$f" -nt "$target" ]; then
					action "promote (newer wins) $f -> $target"
					if ! $DRY_RUN; then
						mv "$f" "$target"
					fi
					PROMOTED=$((PROMOTED + 1))
				else
					action "skip (older or same) $f (keeping $target)"
					if ! $DRY_RUN; then
						rm -f "$f"
					fi
					SKIPPED=$((SKIPPED + 1))
				fi
			else
				action "promote $f -> $target"
				if ! $DRY_RUN; then
					mv "$f" "$target"
				fi
				PROMOTED=$((PROMOTED + 1))
			fi
		done
	done
fi

# ── 3. Move flat handoffs into handoffs/ subdir per project ───────────────
HANDOFFS_MOVED=0
if [ -d "$PROJECTS_DIR" ]; then
	for proj in "$PROJECTS_DIR"/*/memory; do
		[ -d "$proj" ] || continue
		local_handoffs="$proj/handoffs"
		for h in "$proj"/handoff_*.md; do
			[ -f "$h" ] || continue
			action "move handoff $h -> $local_handoffs/"
			if ! $DRY_RUN; then
				mkdir -p "$local_handoffs"
				mv "$h" "$local_handoffs/"
			fi
			HANDOFFS_MOVED=$((HANDOFFS_MOVED + 1))
		done
	done
fi

# ── 4. Strip dangling references from each project's MEMORY.md ────────────
# Two kinds of stale lines:
#   a. Session handoff entries (now bounded by the handoffs/ subdir, not indexed)
#   b. User-level promoted entries pointing at files no longer in this dir
INDEXES_CLEANED=0
if [ -d "$PROJECTS_DIR" ]; then
	for idx in "$PROJECTS_DIR"/*/memory/MEMORY.md; do
		[ -f "$idx" ] || continue
		proj_dir="$(dirname "$idx")"
		cleaned=false
		tmp=$(mktemp)
		cp "$idx" "$tmp"

		# 4a. Strip handoff entries
		if grep -q '\[Session handoff' "$tmp" 2>/dev/null; then
			action "strip handoff lines from $idx"
			if ! $DRY_RUN; then
				tmp2=$(mktemp)
				grep -v '\[Session handoff' "$tmp" >"$tmp2" || true
				mv "$tmp2" "$tmp"
			fi
			cleaned=true
		fi

		# 4b. Strip lines pointing at user-level files no longer in this dir
		# Extract markdown link targets, e.g. `[Title](filename.md), ...`
		while IFS= read -r line; do
			target=$(printf '%s' "$line" | grep -oE '\([a-zA-Z0-9_./-]+\.md\)' | head -1 | tr -d '()')
			[ -z "$target" ] && continue
			[ "$target" = "MEMORY.md" ] && continue
			# If target file no longer exists in this project memory dir but does exist globally,
			# the entry is now stale and should be removed.
			if [ ! -f "$proj_dir/$target" ] && [ -f "$GLOBAL_DIR/$target" ]; then
				action "strip dangling index entry pointing at promoted '$target' in $idx"
				if ! $DRY_RUN; then
					tmp3=$(mktemp)
					# shellcheck disable=SC2016
					grep -v -F "($target)" "$tmp" >"$tmp3" || true
					mv "$tmp3" "$tmp"
				fi
				cleaned=true
			fi
		done < <(grep -E '^\s*-\s+\[' "$tmp" || true)

		if $cleaned && ! $DRY_RUN; then
			mv "$tmp" "$idx"
			INDEXES_CLEANED=$((INDEXES_CLEANED + 1))
		else
			rm -f "$tmp"
			$cleaned && INDEXES_CLEANED=$((INDEXES_CLEANED + 1))
		fi
	done
fi

# ── Report ────────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "Memory migration summary"
$DRY_RUN && echo "(DRY RUN, no changes written)"
echo "  user-level files promoted to global tier:  $PROMOTED"
echo "  user-level files skipped (older copy):     $SKIPPED"
echo "  user-level files refused (template stub):  $REFUSED"
echo "  flat handoffs moved into handoffs/ subdir: $HANDOFFS_MOVED"
echo "  project MEMORY.md indexes cleaned:         $INDEXES_CLEANED"
echo "──────────────────────────────────────────────"
exit 0
