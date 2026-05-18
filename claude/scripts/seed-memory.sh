#!/usr/bin/env bash
# Seeds Claude memory files for the current project from templates.
# Run from the project root after cloning on a new machine.
#
# Also seeds the per-machine GLOBAL memory tier at ~/.claude/memory/ on
# first run. The global tier holds cross-project user-level facts (identity,
# cross-project preferences) that load once per session via
# ~/.claude/hooks/load-global-memory.sh.
#
# Usage: bash ~/.claude/scripts/seed-memory.sh

set -euo pipefail

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"
TEMPLATES="$DOTFILES/claude/memory-templates"
GLOBAL_TEMPLATES="$TEMPLATES/global"

# ── Global tier (per-machine; seeded once, never overwritten) ──────────────
GLOBAL_DIR="$HOME/.claude/memory"
if [ -d "$GLOBAL_TEMPLATES" ]; then
	if [ ! -d "$GLOBAL_DIR" ]; then
		mkdir -p "$GLOBAL_DIR"
		echo "Seeding global memory tier at $GLOBAL_DIR"
		for template in "$GLOBAL_TEMPLATES"/*.md; do
			[ -f "$template" ] || continue
			filename="$(basename "$template")"
			cp "$template" "$GLOBAL_DIR/$filename"
			echo "  seeded  global/$filename"
		done
	else
		# Top up missing files only, never overwrite existing global content.
		for template in "$GLOBAL_TEMPLATES"/*.md; do
			[ -f "$template" ] || continue
			filename="$(basename "$template")"
			if [ ! -f "$GLOBAL_DIR/$filename" ]; then
				cp "$template" "$GLOBAL_DIR/$filename"
				echo "  topped-up  global/$filename"
			fi
		done
	fi
fi

# ── Project tier ───────────────────────────────────────────────────────────
PROJECT_PATH="$(pwd)"
ENCODED="${PROJECT_PATH//\//-}"
MEMORY_DIR="$HOME/.claude/projects/${ENCODED}/memory"

mkdir -p "$MEMORY_DIR"
mkdir -p "$MEMORY_DIR/handoffs"

for template in "$TEMPLATES"/*.md; do
	[ -f "$template" ] || continue
	filename="$(basename "$template")"
	if [ -f "$MEMORY_DIR/$filename" ]; then
		echo "  exists  $filename (skipped)"
		continue
	fi
	cp "$template" "$MEMORY_DIR/$filename"
	echo "  seeded  $filename"
done

echo ""
echo "Memory seeded at: $MEMORY_DIR"
echo "Global tier:      $GLOBAL_DIR"
echo "Edit project_current_phase.md to reflect the current project state."
