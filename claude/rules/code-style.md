---
name: code-style
description: Writing, JSON, SQL, and shell formatting conventions enforced across all edits
---

# Code and Writing Style

## Em dashes are forbidden (hard rule, enforced)
**Never emit U+2014 (em dash) in any output: code, comments, docs, commit messages, PR descriptions, or assistant prose.** This applies to every channel, every file type, every response.

Substitute with one of:
- a comma, when the dash marks a brief pause or apposition
- a semicolon, when joining two independent clauses
- parentheses, when the dashed text is a true aside
- a period, splitting into separate sentences
- the literal word "to", for numeric or alphabetic ranges

Enforcement: the `block-em-dash.sh` PreToolUse hook denies any `Write`, `Edit`, `MultiEdit`, or `NotebookEdit` whose payload contains a U+2014. If this hook fires, the tool call is rejected before it touches disk; rewrite the payload without the em dash and retry. Do not work around it with `sed` or shell heredocs; the rule is the same regardless of channel.

## Writing style
- Never use causal framing ("This is because..."). State the fact directly.
- No emojis in code, comments, commit messages, or prose unless requested.
- Commit messages: imperative mood, concise, no trailing period.

## JSON formatting
- Use 4-space indentation in all JSON files. Enforced automatically by the post-edit hook via `jq --indent 4`.

## SQL formatting
- Format all SQL files to sqlfmt style: all keywords lowercase, 4-space indentation, line_length=120.
- Do not use jinja formatting. sqlfmt is jinja-aware and preserves jinja expressions as-is; this applies to both dbt and non-dbt SQL.
- In dbt projects, sqlfmt config lives in `[tool.sqlfmt]` in `pyproject.toml`. Write SQL that passes sqlfmt without modification.
- The post-edit hook auto-applies sqlfmt when found in the project venv (`.venv/bin/sqlfmt`) or on PATH.

## Shell formatting
- All shell scripts (`.sh`) are formatted with `shfmt`. Style: tabs for indentation (`-i 0`), binary ops at line start (`-bn`), indented switch cases (`-ci`).
- `shfmt -w -i 0 -bn -ci` is applied automatically by the post-edit hook on every save and enforced at pre-commit via `shfmt-lint-staged.sh`. Write shell that passes `shfmt` without modification.
- `shellcheck` runs after `shfmt` for linting. Both are informational in the post-edit hook; `shfmt` is blocking at pre-commit (`SKIP_SHFMT=1 git commit` to bypass).
- Multi-line commands with backslash continuations are fine for readability. Only split at argument or flag boundaries, never inside a quoted string. A backslash continuation must appear outside of all quotes.
- In code blocks containing shell commands, do not indent the command itself. Keep it flush-left within the block.
