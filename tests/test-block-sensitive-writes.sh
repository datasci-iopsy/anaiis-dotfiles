#!/usr/bin/env bash
# tests/test-block-sensitive-writes.sh -- verify block-sensitive-writes.sh
#
# Confirms the hook denies writes to .env, credentials, key, and secret files
# while allowing safe paths (.env.example, .env.template, source files).
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

make_read_input() {
	printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$1"
}

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

# ── 7. Read tool: centralized .env protection ─────────────────────────────────
# settings.json's Read(**/.env*) / Edit(**/.env*) globs matched .env.example
# and .env.template too, contradicting this hook's own carve-out (which only
# ran for Write/Edit until now). Protection for the .env family is
# centralized here so the same carve-out applies to Read as well.

echo
echo "--- 7. Read tool: .env family"

assert_exit "7.1 Read .env denied" 2 "$(make_read_input '/project/.env')"
assert_exit "7.2 Read .env.production denied" 2 "$(make_read_input '/project/.env.production')"
assert_exit "7.3 Read .env.example allowed" 0 "$(make_read_input '/project/.env.example')"
assert_exit "7.4 Read .env.template allowed" 0 "$(make_read_input '/project/.env.template')"

echo
echo "--- 8. Read tool: narrower pattern set than Write/Edit"
# .lock and bare *secret*-substring stay in the Write/Edit set (unchanged,
# see section 3/4) but must NOT extend to Read -- package-lock.json and a
# file merely named secrets-architecture.md are ordinary, frequently-read
# source files, not secrets.

assert_exit "8.1 Read package-lock.json allowed" 0 "$(make_read_input '/project/package-lock.json')"
assert_exit "8.2 Read uv.lock allowed" 0 "$(make_read_input '/project/uv.lock')"
assert_exit "8.3 Read secrets-architecture.md allowed" 0 "$(make_read_input '/project/docs/secrets-architecture.md')"

echo
echo "--- 9. Write/Edit behavior unchanged (regression)"

assert_exit "9.1 Write .lock still denied" 2 "$(make_write_input '/project/some.lock')"

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
