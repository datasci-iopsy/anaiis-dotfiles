#!/usr/bin/env bash
# block-em-dash.sh, deny Edit/Write/MultiEdit/NotebookEdit payloads
# containing U+2014 (em dash). Enforces the rule in
# ~/.claude/rules/code-style.md across every Claude-initiated write.
#
# Input:  PreToolUse JSON on stdin.
# Output: stderr message + exit 2 to deny on em dash; exit 0 otherwise.
#
# Fails open (exits 0) when jq is missing so the harness is never
# bricked by tooling absence; the repo pre-commit hook and post-edit
# lint hook serve as independent backstops.

set -u

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

case "$TOOL" in
	Write)
		PAYLOAD=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')
		;;
	Edit)
		PAYLOAD=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""')
		;;
	MultiEdit)
		PAYLOAD=$(printf '%s' "$INPUT" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")')
		;;
	NotebookEdit)
		PAYLOAD=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_source // ""')
		;;
	*)
		exit 0
		;;
esac

# U+2014 in UTF-8 is the byte sequence E2 80 94.
EM_DASH=$'\xe2\x80\x94'
if printf '%s' "$PAYLOAD" | grep -qF -- "$EM_DASH"; then
	FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // "(unknown)"')
	{
		printf '[em-dash-guard] BLOCKED: %s payload for %s contains an em dash (U+2014).\n' "$TOOL" "$FILE"
		printf 'Per ~/.claude/rules/code-style.md, em dashes are forbidden in code, docs, and prose.\n'
		printf 'Substitute with a comma, semicolon, parenthesis, or separate sentences.\n'
	} >&2
	exit 2
fi

exit 0
