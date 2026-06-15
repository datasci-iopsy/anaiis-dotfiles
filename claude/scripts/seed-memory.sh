#!/usr/bin/env bash
# Seeds Claude PROJECT-tier memory files for the current project from
# templates. Run from the project root after cloning on a new machine.
#
# The GLOBAL memory tier needs no seeding: it is git-tracked in the dotfiles
# repo at claude/memory/ and symlinked to ~/.claude/memory by install.sh.
# Verify with: [ -L ~/.claude/memory ]
#
# Usage: bash ~/.claude/scripts/seed-memory.sh

set -euo pipefail

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"
TEMPLATES="$DOTFILES/claude/memory-templates"

if [ ! -L "$HOME/.claude/memory" ]; then
	echo "warning: ~/.claude/memory is not a symlink into the dotfiles repo." >&2
	echo "         Run install.sh (and merge any local files into claude/memory/ first)." >&2
elif ! _mem_target="$(realpath "$HOME/.claude/memory" 2>/dev/null)" \
	|| [ "$_mem_target" != "$DOTFILES/claude/memory" ]; then
	echo "warning: ~/.claude/memory symlink does not point to $DOTFILES/claude/memory." >&2
	echo "         Resolved: ${_mem_target:-unresolvable}. Run install.sh to fix." >&2
fi

# ── Project tier ───────────────────────────────────────────────────────────
PROJECT_PATH="$(pwd)"
ENCODED=$(echo "$PROJECT_PATH" | tr '/.' '-')
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
echo "Edit project_current_phase.md to reflect the current project state."
