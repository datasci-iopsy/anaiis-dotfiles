#!/usr/bin/env bash
# sqlfmt-lint-staged.sh -- format staged SQL files with sqlfmt and re-stage
#
# Designed to be called from a repo's .git/hooks/pre-commit.
# Formats staged SQL files in-place; re-stages any files changed by sqlfmt.
# Bypass: SKIP_SQLFMT=1 git commit

set -euo pipefail

[ "${SKIP_SQLFMT:-0}" = "1" ] && exit 0

SQL_FILES=()
while IFS= read -r f; do
	[[ "$f" =~ \.sql$ ]] && [ -f "$f" ] && SQL_FILES+=("$f")
done < <(git diff --cached --name-only)

[ ${#SQL_FILES[@]} -eq 0 ] && exit 0

SQLFMT=""
if command -v sqlfmt &>/dev/null; then
	SQLFMT="sqlfmt"
elif [[ -x "$HOME/.local/bin/sqlfmt" ]]; then
	SQLFMT="$HOME/.local/bin/sqlfmt"
fi

if [[ -z "$SQLFMT" ]]; then
	echo "[sqlfmt] sqlfmt not found -- skipping SQL format" >&2
	exit 0
fi

echo "[sqlfmt] Formatting ${#SQL_FILES[@]} staged SQL file(s)..."

# Use project pyproject.toml config if present; otherwise default to line_length=120.
if grep -qs '\[tool\.sqlfmt\]' pyproject.toml 2>/dev/null; then
	$SQLFMT "${SQL_FILES[@]}" 2>&1
else
	$SQLFMT --line-length 120 "${SQL_FILES[@]}" 2>&1
fi

# Re-stage any files that sqlfmt modified
REFORMATTED=()
for f in "${SQL_FILES[@]}"; do
	if ! git diff --quiet -- "$f"; then
		git add "$f"
		REFORMATTED+=("$f")
	fi
done

if [[ ${#REFORMATTED[@]} -gt 0 ]]; then
	echo "[sqlfmt] Auto-formatted and re-staged: ${REFORMATTED[*]}" >&2
fi

echo "[sqlfmt] Done."
exit 0
