---
name: code-style
description: ASD-STE100 as the default writing register for all prose, plus JSON, SQL, and shell formatting conventions enforced across all edits
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

## Default register: ASD-STE100

All prose Claude writes follows ASD-STE100 (Simplified Technical English): responses, plans, tasks, specs, reports, code comments, docstrings, commit bodies, and PR descriptions. The tiers in `rules/session.md` set how much to write. This section sets how to write it.

Sentence rules:
- One topic per sentence. In procedures, one instruction per sentence.
- Descriptive sentences: 25 words or fewer. Procedural sentences: 20 words or fewer.
- Active voice, with the actor named: "the hook writes the file", not "the file is written".
- Present tense for facts and behavior. Imperative for instructions. Simple past for events that occurred.
- Do not use the `-ing` form of a verb, except as part of a technical name or as a modifier.
- Put the condition before the instruction: "If the file is absent, exit 0."

Word rules:
- One word, one meaning. Use the same term for the same thing every time. Do not rotate synonyms for variety.
- Noun clusters of three words or fewer. Break longer clusters apart with "of", "for", or "that".
- Keep articles ("the", "a") and write full sentences. Telegraphic prose ("update threshold in hook") is not STE; write "Update the threshold in the hook."
- No slang, no idiom, no filler ("basically", "essentially", "sort of"), no rhetorical questions.
- Use technical names and technical verbs as their domain writes them (`jq`, `PostToolUse`, `vapply`, likelihood, gradient). Do not paraphrase them.

Structure rules:
- Paragraphs of six sentences or fewer. The first sentence states the topic.
- Use numbered steps for a sequence and a bullet list for a set.
- Put warnings and cautions before the step they apply to.

Complex logic and mathematical modeling: clarity beats brevity. Terse means no padding, not less content.
- Define each symbol and each term the first time it appears.
- State each assumption and each input before the result.
- Describe the mechanism step by step: what goes in, what changes it, what comes out. One transform per sentence.
- When you introduce a formula or an algorithm, show one worked example with concrete values.
- When a reader could assume a step does something it does not do, say so.

Exception: when Claude edits or drafts text in the voice of a user-owned document, that text keeps the document's register. Examples: manuscript copyedits, and academic prose the user asked for in APA style. Claude's own comments on that document stay in STE.

## JSON formatting
- Use 4-space indentation in all JSON files. Enforced automatically by the post-edit hook via `jq --indent 4`.

## SQL formatting
- Format all SQL files to sqlfmt style: all keywords lowercase, 4-space indentation, line_length=120.
- Do not use jinja formatting. sqlfmt is jinja-aware and preserves jinja expressions as-is; this applies to both dbt and non-dbt SQL.
- In dbt projects, sqlfmt config lives in `[tool.sqlfmt]` in `pyproject.toml`. Write SQL that passes sqlfmt without modification.
- The post-edit hook auto-applies sqlfmt when found in the project venv (`.venv/bin/sqlfmt`) or on PATH.
- `sqlfmt --check` runs at pre-commit via `sqlfmt-lint-staged.sh` and blocks commits with format drift (`SKIP_SQLFMT=1 git commit` to bypass).

## Shell formatting
- All shell scripts (`.sh`) are formatted with `shfmt`. Style: tabs for indentation (`-i 0`), binary ops at line start (`-bn`), indented switch cases (`-ci`).
- `shfmt -w -i 0 -bn -ci` is applied automatically by the post-edit hook on every save and enforced at pre-commit via `shfmt-lint-staged.sh`. Write shell that passes `shfmt` without modification.
- `shellcheck` runs after `shfmt` for linting. Both are informational in the post-edit hook; `shfmt` is blocking at pre-commit (`SKIP_SHFMT=1 git commit` to bypass).
- Multi-line commands with backslash continuations are fine for readability. Only split at argument or flag boundaries, never inside a quoted string. A backslash continuation must appear outside of all quotes.
- In code blocks containing shell commands, do not indent the command itself. Keep it flush-left within the block.

## Match the codebase's conventions, even if you disagree

If the codebase uses snake_case, use snake_case. If it uses class-based components, use class-based components. If it wraps errors one way, wrap them the same way. Conformance beats taste inside an existing codebase.

If you genuinely believe a convention is harmful, surface it as a separate observation after the task is complete. Do not silently fork: introducing a second pattern alongside the existing one is worse than either pattern alone. The observation belongs in a comment or a follow-up, not in the code you are writing now.
