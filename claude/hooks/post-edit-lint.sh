#!/usr/bin/env bash
# post-edit-lint.sh -- PostToolUse lint hook
#
# Runs linters after Claude edits Python, Shell, or R files.
# Always exits 0 (informational only -- never blocks Claude).
#
# Triggered by: PostToolUse on Edit|Write
# Reads: JSON from stdin (tool_name, tool_input.file_path, ...)

INPUT=$(cat)
FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null <<<"$INPUT")

[ -z "$FILE" ] && exit 0

case "$FILE" in

	*.py)
		RUFF=""
		if command -v ruff &>/dev/null; then
			RUFF="ruff"
		elif [[ -x "$HOME/.local/bin/ruff" ]]; then
			RUFF="$HOME/.local/bin/ruff"
		fi
		if [[ -n "$RUFF" ]]; then
			echo "[lint] ruff check --fix: $FILE" >&2
			$RUFF check --fix --quiet "$FILE" 2>&1 | head -5
			echo "[lint] ruff format: $FILE" >&2
			$RUFF format --quiet "$FILE" 2>&1
		fi
		;;

	*.sh)
		if command -v shfmt &>/dev/null; then
			echo "[lint] shfmt: $FILE" >&2
			shfmt -w -i 0 -bn -ci "$FILE" 2>&1
		fi
		if command -v shellcheck &>/dev/null; then
			echo "[lint] shellcheck: $FILE" >&2
			shellcheck --severity=warning "$FILE" 2>&1 | head -5
		fi
		;;

	*.json)
		if command -v jq &>/dev/null; then
			if formatted=$(jq --indent 4 . "$FILE" 2>&1); then
				echo "$formatted" >"$FILE"
				echo "[lint] json: formatted $FILE with 4-space indent" >&2
			else
				echo "[lint] json: parse error in $FILE -- $formatted" >&2
			fi
		fi
		;;

	*.sql)
		SQLFMT=""
		if command -v sqlfmt &>/dev/null; then
			SQLFMT="sqlfmt"
		elif [[ -x "$HOME/.local/bin/sqlfmt" ]]; then
			SQLFMT="$HOME/.local/bin/sqlfmt"
		fi
		if [[ -n "$SQLFMT" ]]; then
			# Use project pyproject.toml config if present; otherwise default to line_length=120.
			# Installed without [jinjafmt] extra: sqlfmt is jinja-aware but does not reformat
			# jinja expressions -- correct for both dbt and non-dbt SQL.
			if grep -qs '\[tool\.sqlfmt\]' pyproject.toml 2>/dev/null; then
				echo "[lint] sqlfmt: $FILE (using project config)" >&2
				$SQLFMT "$FILE" 2>&1
			else
				echo "[lint] sqlfmt: $FILE (line-length 120)" >&2
				$SQLFMT --line-length 120 "$FILE" 2>&1
			fi
		else
			echo "[lint] sqlfmt not found -- skipping SQL format" >&2
		fi
		;;

	*.R | *.r)
		if ! command -v Rscript &>/dev/null; then
			exit 0
		fi
		if ! Rscript --no-init-file --quiet -e "if (!requireNamespace('lintr', quietly=TRUE)) quit(status=1)" &>/dev/null; then
			echo "[lint] lintr not installed -- run: install.packages('lintr')" >&2
			exit 0
		fi
		echo "[lint] lintr: $FILE" >&2
		# --no-init-file: bypass renv/.Rprofile so global lintr is used
		# Pass path via env var to handle spaces and special characters safely
		LINTR_FILE="$FILE" Rscript --no-init-file --quiet \
			-e "lintr::lint(Sys.getenv('LINTR_FILE'))" 2>&1 | head -10
		;;

esac

exit 0
