#!/usr/bin/env bash
# block-sensitive-writes.sh: deny Read/Write/Edit of credentials, secrets, and
# key files. Allows Read/Write/Edit of *.env.example and *.env.template
# (non-secret scaffolding). Sole enforcement point for the .env family across
# all three tools -- settings.json's own Read/Edit globs can't express an
# exception for the template files (no negation, deny always wins), so that
# carve-out lives here instead.
#
# Input:  PreToolUse JSON on stdin.
# Output: stderr message + exit 2 to deny; exit 0 otherwise.
#
# Fails open when jq is missing.

set -u

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
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
esac

if [ "$TOOL" = "Read" ]; then
	# Narrower than Write/Edit below: .lock and a bare *secret* substring in
	# the path (package-lock.json, uv.lock, secrets-architecture.md) are
	# ordinary, frequently-read source files, not secrets. Read never had
	# this hook's protection before (Write|Edit was the only matcher), so
	# only the .env family -- the thing settings.json's Read glob got wrong --
	# is added here, not the full Write/Edit set.
	case "$FILE" in
		*.env | *.env.*)
			log_secret_block "read-guard:sensitive-file" "$FILE"
			printf 'BLOCK: Refusing read of sensitive file: %s\n' "$FILE" >&2
			exit 2
			;;
	esac
else
	case "$FILE" in
		*.lock | *.env | *.env.* | *credentials* | *secret* | *.pem | *.key)
			log_secret_block "write-guard:sensitive-file" "$FILE"
			printf 'BLOCK: Refusing write to sensitive file: %s\n' "$FILE" >&2
			exit 2
			;;
	esac
fi

exit 0
