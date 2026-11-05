#!/usr/bin/env bash
# Seeds Claude PROJECT-tier memory files for the current project from
# templates. Run from the project root after cloning on a new machine.
#
# The GLOBAL memory tier needs no seeding: install.sh makes ~/.claude/memory
# a local folder with a MEMORY.md index. Verify with: [ -d ~/.claude/memory ]
#
# Usage: bash ~/.claude/scripts/seed-memory.sh

set -euo pipefail

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"
TEMPLATES="$DOTFILES/claude/memory-templates"

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
