#!/usr/bin/env bash
# tests/test-block-sensitive-writes.sh -- verify block-sensitive-writes.sh
#
# Confirms the hook denies writes to .env, credentials, key, and secret files
# while allowing safe paths (.env.example, .env.template, source files).
# Also verifies the jq fail-open guard in source.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/block-sensitive-writes.sh"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

PASS=0
FAIL=0

pass() {
	printf '  PASS  %s\n' "$1"
	PASS=$((PASS + 1))
}

fail() {
	printf '  FAIL  %s\n' "$1"
	FAIL=$((FAIL + 1))
}

assert_exit() {
	local label="$1" want="$2" json="$3"
	local got
	got=$(
		printf '%s' "$json" | HOME="$TEST_HOME" bash "$HOOK" 2>/dev/null
		echo $?
	)
	if [ "$got" = "$want" ]; then
		pass "$label"
	else
		fail "$label (got exit=$got, want $want)"
	fi
}

make_write_input() {
	printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1"
}

# ── 1. Hook file present and executable ───────────────────────────────────────

echo
echo "--- 1. Hook file"

if [ -f "$HOOK" ]; then
	pass "1.1 hook exists"
else
	fail "1.1 hook missing: $HOOK"
fi

if [ -x "$HOOK" ]; then
	pass "1.2 hook executable"
else
	fail "1.2 hook not executable"
fi

# ── 2. jq fail-open guard in source ───────────────────────────────────────────

echo
echo "--- 2. jq fail-open guard"

if grep -qE 'command -v jq.*(exit 0|\|\| exit 0)' "$HOOK"; then
	pass "2.1 jq fail-open guard present in source"
else
	fail "2.1 jq fail-open guard missing from source"
fi

# ── 3. Denied: sensitive file paths ───────────────────────────────────────────

echo
echo "--- 3. Sensitive files denied"

assert_exit "3.1 .env denied" 2 "$(make_write_input '/project/.env')"
assert_exit "3.2 .env.production denied" 2 "$(make_write_input '/project/.env.production')"
assert_exit "3.3 credentials.json denied" 2 "$(make_write_input '/project/credentials.json')"
assert_exit "3.4 .pem denied" 2 "$(make_write_input '/project/server.pem')"
assert_exit "3.5 .key denied" 2 "$(make_write_input '/project/private.key')"
assert_exit "3.6 secret file denied" 2 "$(make_write_input '/project/api_secret.txt')"

# ── 4. Allowed: safe scaffolding and source files ─────────────────────────────

echo
echo "--- 4. Safe files allowed"

assert_exit "4.1 .env.example allowed" 0 "$(make_write_input '/project/.env.example')"
assert_exit "4.2 .env.template allowed" 0 "$(make_write_input '/project/.env.template')"
assert_exit "4.3 .md allowed" 0 "$(make_write_input '/project/README.md')"
assert_exit "4.4 .py allowed" 0 "$(make_write_input '/project/script.py')"
assert_exit "4.5 config.yaml allowed" 0 "$(make_write_input '/project/config.yaml')"

# ── 5. No file_path field is a no-op ──────────────────────────────────────────

echo
echo "--- 5. No file_path is a no-op"

assert_exit "5.1 missing file_path passes" 0 \
	'{"tool_name":"Write","tool_input":{"content":"x"}}'

# ── 6. Secret-access block logging ────────────────────────────────────────────

echo
echo "--- 6. Secret-access block logging"

LOG_FILE="$TEST_HOME/.claude/logs/secret-access-blocks.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE"

log_lines() { wc -l <"$LOG_FILE" | tr -d ' '; }

BEFORE=$(log_lines)
printf '%s' "$(make_write_input '/project/.env')" | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>&1
AFTER=$(log_lines)
if [ "$AFTER" -gt "$BEFORE" ] && tail -1 "$LOG_FILE" | grep -qE $'\twrite-guard:sensitive-file\t'; then
	pass "6.1 sensitive write block appends a log line"
else
	fail "6.1 sensitive write block should append a log line (before=$BEFORE after=$AFTER)"
fi

BEFORE=$(log_lines)
printf '%s' "$(make_write_input '/project/README.md')" | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>&1
AFTER=$(log_lines)
if [ "$AFTER" -eq "$BEFORE" ]; then
	pass "6.2 allowed write appends no log line"
else
	fail "6.2 allowed write should not log (before=$BEFORE after=$AFTER)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
