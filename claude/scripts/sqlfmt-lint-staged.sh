#!/usr/bin/env bash
# sqlfmt-lint-staged.sh -- run sqlfmt format check on staged SQL files
#
# Designed to be called from a repo's .git/hooks/pre-commit.
# Exits 1 (blocks commit) if any sqlfmt findings exist.
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
	echo "[sqlfmt] sqlfmt not found -- skipping SQL format check" >&2
	exit 0
fi

echo "[sqlfmt] Checking ${#SQL_FILES[@]} staged SQL file(s)..."

# Use project pyproject.toml config if present; otherwise default to line_length=120.
if grep -qs '\[tool\.sqlfmt\]' pyproject.toml 2>/dev/null; then
	if ! $SQLFMT --check "${SQL_FILES[@]}" 2>&1; then
		echo ""
		echo "[sqlfmt] Format issues found. Run: sqlfmt ${SQL_FILES[*]}"
		echo "         To bypass: SKIP_SQLFMT=1 git commit ..."
		echo ""
		exit 1
	fi
else
	if ! $SQLFMT --check --line-length 120 "${SQL_FILES[@]}" 2>&1; then
		echo ""
		echo "[sqlfmt] Format issues found. Run: sqlfmt --line-length 120 ${SQL_FILES[*]}"
		echo "         To bypass: SKIP_SQLFMT=1 git commit ..."
		echo ""
		exit 1
	fi
fi

echo "[sqlfmt] No issues found."
exit 0
