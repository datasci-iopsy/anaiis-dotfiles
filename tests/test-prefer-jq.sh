#!/usr/bin/env bash
# tests/test-prefer-jq.sh -- verify prefer-jq.sh
#
# Confirms the hook blocks python/python3 commands where json is the only
# import (pure parsing task) and passes commands that import additional
# packages alongside json, or that don't involve json parsing at all.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/prefer-jq.sh"

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
	local label="$1" want="$2" cmd="$3"
	local json got
	# jq --arg properly escapes quotes and special chars in $cmd
	json=$(jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
	got=$(
		printf '%s' "$json" | bash "$HOOK" 2>/dev/null
		echo $?
	)
	if [ "$got" = "$want" ]; then
		pass "$label"
	else
		fail "$label (got exit=$got, want $want)"
	fi
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

# ── 2. Denied: python with json as sole import ────────────────────────────────

echo
echo "--- 2. Pure json import blocked"

assert_exit "2.1 python -c 'import json; ...' blocked" 2 \
	"python -c 'import json; print(json.dumps({}))')"
assert_exit "2.2 python3 -c 'import json; ...' blocked" 2 \
	"python3 -c 'import json; d=json.loads(open(\"f\").read())'"

# ── 3. Allowed: json imported alongside other packages ────────────────────────

echo
echo "--- 3. json + other imports pass"

assert_exit "3.1 import json, pandas passes" 0 \
	"python -c 'import json, pandas; print(1)'"
assert_exit "3.2 import pandas then import json passes" 0 \
	"python3 -c 'import pandas; import json; print(1)'"

# ── 4. Allowed: no json import ────────────────────────────────────────────────

echo
echo "--- 4. Commands without json import pass"

assert_exit "4.1 python without json passes" 0 \
	"python -c 'import os; print(os.getcwd())'"
assert_exit "4.2 non-python command passes" 0 \
	"jq '.foo' file.json"
assert_exit "4.3 bash command passes" 0 \
	"ls -la"

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
