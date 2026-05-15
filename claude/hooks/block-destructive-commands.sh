#!/usr/bin/env bash
# block-destructive-commands.sh: deny destructive bq, gcloud, and uv subcommands.
# Supplements the deny list in settings.json for commands that require regex matching.
#
# Input:  PreToolUse JSON on stdin.
# Output: stderr message + exit 2 to deny; exit 0 otherwise.
#
# Fails open when jq is missing.

set -u

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && exit 0

if printf '%s' "$CMD" | grep -qE '^bq\s+rm\b'; then
	printf 'BLOCK: bq rm is destructive. Run this manually in terminal.\n' >&2
	exit 2
fi

if printf '%s' "$CMD" | grep -qE '^gcloud\s.*(delete|destroy|remove-iam-policy|set-iam-policy|disable|reset-windows-password)'; then
	printf 'BLOCK: Destructive gcloud command detected. Run this manually in terminal.\n' >&2
	exit 2
fi

if printf '%s' "$CMD" | grep -qE '^uv\s+(cache\s+(clean|prune)|publish|tool\s+uninstall|pip\s+uninstall)'; then
	printf 'BLOCK: Destructive uv command detected. Run this manually in terminal.\n' >&2
	exit 2
fi

exit 0
