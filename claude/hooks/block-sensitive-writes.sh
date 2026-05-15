#!/usr/bin/env bash
# block-sensitive-writes.sh: deny Write/Edit to credentials, secrets, and key files.
# Allows writes to *.env.example and *.env.template (non-secret scaffolding).
#
# Input:  PreToolUse JSON on stdin.
# Output: stderr message + exit 2 to deny; exit 0 otherwise.
#
# Fails open when jq is missing.

set -u

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] && exit 0

case "$FILE" in
	*.env.example | *.env.template)
		exit 0
		;;
	*.lock | *.env | *.env.* | *credentials* | *secret* | *.pem | *.key)
		printf 'BLOCK: Refusing write to sensitive file: %s\n' "$FILE" >&2
		exit 2
		;;
esac

exit 0
