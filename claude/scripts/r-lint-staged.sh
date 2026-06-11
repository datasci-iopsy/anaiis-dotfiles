#!/usr/bin/env bash
# r-lint-staged.sh -- format staged R files with styler, then check with lintr
#
# Designed to be called from a repo's .git/hooks/pre-commit.
# Step 1: styler auto-formats staged R files in-place (indent_by=4, tidyverse_style).
#         Re-stages any files changed by styler.
# Step 2: lintr checks staged R files; blocks commit on semantic findings.
#
# Bypass flags:
#   SKIP_R_LINT=1     git commit  -- skip entire hook (format + lint)
#   SKIP_R_FORMAT=1   git commit  -- skip styler auto-format step only
#   SKIP_LINTR=1      git commit  -- skip lintr check step only
#
# Usage in pre-commit hook:
#   bash "$HOME/.claude/scripts/r-lint-staged.sh"

set -euo pipefail

[ "${SKIP_R_LINT:-0}" = "1" ] && exit 0

# Collect staged R files that exist on disk
R_FILES=()
while IFS= read -r f; do
	[[ "$f" =~ \.[Rr]$ ]] && [ -f "$f" ] && R_FILES+=("$f")
done < <(git diff --cached --name-only)

[ ${#R_FILES[@]} -eq 0 ] && exit 0

if ! command -v Rscript &>/dev/null; then
	echo "[r-lint] Rscript not found -- skipping R hooks" >&2
	exit 0
fi

# --- Step 1: Auto-format with styler ---
if [ "${SKIP_R_FORMAT:-0}" != "1" ]; then
	if Rscript --no-init-file --quiet \
		-e "if (!requireNamespace('styler', quietly=TRUE)) quit(status=1)" &>/dev/null; then
		echo "[r-format] Formatting ${#R_FILES[@]} staged R file(s)..."
		Rscript --no-init-file --quiet -e "
      files <- commandArgs(trailingOnly = TRUE)
      for (f in files) {
        styler::style_file(f, style = styler::tidyverse_style, indent_by = 4L)
      }
    " "${R_FILES[@]}" 2>/dev/null
		REFORMATTED=()
		for f in "${R_FILES[@]}"; do
			if ! git diff --quiet -- "$f"; then
				git add "$f"
				REFORMATTED+=("$f")
			fi
		done
		if [ ${#REFORMATTED[@]} -gt 0 ]; then
			echo "[r-format] Auto-formatted and re-staged: ${REFORMATTED[*]}" >&2
		fi
		echo "[r-format] Done."
	else
		echo "[r-format] styler not installed -- skipping auto-format" >&2
	fi
fi

# --- Step 2: Lint with lintr ---
[ "${SKIP_LINTR:-0}" = "1" ] && exit 0

if ! Rscript --no-init-file --quiet \
	-e "if (!requireNamespace('lintr', quietly=TRUE)) quit(status=1)" &>/dev/null; then
	echo "[r-lint] lintr not installed -- skipping (run: install.packages('lintr'))" >&2
	exit 0
fi

echo "[r-lint] Checking ${#R_FILES[@]} staged R file(s)..."

FINDINGS=""
if ! FINDINGS=$(Rscript --no-init-file --quiet -e "
  files <- commandArgs(trailingOnly = TRUE)
  results <- lapply(files, lintr::lint)
  all_results <- do.call(c, results)
  if (length(all_results) > 0) {
    print(all_results)
    quit(status = 1)
  }
" "${R_FILES[@]}" 2>&1); then
	echo ""
	echo "$FINDINGS"
	echo ""
	echo "[r-lint] Fix the above before committing."
	echo "         To bypass: SKIP_R_LINT=1 git commit ..."
	echo ""
	exit 1
fi

echo "[r-lint] No issues found."
exit 0
