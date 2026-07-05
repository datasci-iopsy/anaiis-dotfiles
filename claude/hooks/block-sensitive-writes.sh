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
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

[ -z "$FILE" ] && exit 0

# Append a line to the secret-access block log; best-effort, never blocks.
log_secret_block() {
	local surface="$1" detail="$2"
	local log_dir="$HOME/.claude/logs"
	local safe_session safe_detail
	safe_session=$(printf '%s' "${SESSION_ID:-unknown}" | tr -d '\n\r\t')
	safe_detail=$(printf '%s' "$detail" | tr -d '\n\r\t')
	mkdir -p "$log_dir" 2>/dev/null
	printf '%s\t%s\t%s\t%s\n' \
		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$safe_session" "$surface" "$safe_detail" \
		>>"$log_dir/secret-access-blocks.log" 2>/dev/null || true
}

case "$FILE" in
	*.env.example | *.env.template)
		exit 0
		;;
	*.lock | *.env | *.env.* | *credentials* | *secret* | *.pem | *.key)
		log_secret_block "write-guard:sensitive-file" "$FILE"
		printf 'BLOCK: Refusing write to sensitive file: %s\n' "$FILE" >&2
		exit 2
		;;
esac

exit 0
