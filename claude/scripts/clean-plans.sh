#!/usr/bin/env bash
# clean-plans.sh -- remove plan files older than N days (default: 14)
# Usage: bash ~/.claude/scripts/clean-plans.sh [days]

set -euo pipefail
PLAN_DIR="$HOME/.claude/plans"
DAYS="${1:-14}"

[ ! -d "$PLAN_DIR" ] && echo "No plans directory." && exit 0

OLD_FILES=()
while IFS= read -r -d '' f; do
	OLD_FILES+=("$f")
done < <(find "$PLAN_DIR" -name "*.md" -mtime +"$DAYS" -print0 2>/dev/null | sort -z)

[ ${#OLD_FILES[@]} -eq 0 ] && echo "No plan files older than $DAYS days." && exit 0

# Portable mtime as YYYY-MM-DD (BSD stat on darwin, GNU stat elsewhere)
mtime_ymd() {
	if [[ "$OSTYPE" == darwin* ]]; then
		stat -f '%Sm' -t '%Y-%m-%d' "$1"
	else
		stat -c %y "$1" 2>/dev/null | cut -d' ' -f1
	fi
}

for f in "${OLD_FILES[@]}"; do
	echo "  $(basename "$f")  ($(mtime_ymd "$f"))"
done

echo ""
echo "${#OLD_FILES[@]} plan file(s) older than $DAYS days."
read -rp "Delete? [y/N] " confirm
case "$confirm" in
	[yY])
		rm "${OLD_FILES[@]}"
		echo "Deleted ${#OLD_FILES[@]} file(s)."
		;;
	*) echo "Aborted." ;;
esac
