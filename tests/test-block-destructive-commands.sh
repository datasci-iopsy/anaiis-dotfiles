#!/usr/bin/env bash
# tests/test-block-destructive-commands.sh -- verify block-destructive-commands.sh
#
# Confirms the hook denies destructive bq/gcloud/uv subcommands and passes
# safe ones through. Also verifies the jq fail-open guard exists in source.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/block-destructive-commands.sh"

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
	local label="$1" want="$2"
	local json="$3"
	local got
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

make_input() {
	printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
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

# ── 3. bq deny ────────────────────────────────────────────────────────────────

echo
echo "--- 3. bq rm blocked"

assert_exit "3.1 bq rm blocks" 2 "$(make_input 'bq rm dataset.table')"
assert_exit "3.2 bq rm --force blocks" 2 "$(make_input 'bq rm --force dataset.table')"

# ── 4. bq allow ───────────────────────────────────────────────────────────────

echo
echo "--- 4. bq safe commands pass"

assert_exit "4.1 bq query passes" 0 "$(make_input 'bq query --use_legacy_sql=false "SELECT 1"')"
assert_exit "4.2 bq ls passes" 0 "$(make_input 'bq ls')"
assert_exit "4.3 bq show passes" 0 "$(make_input 'bq show dataset.table')"

# ── 5. gcloud deny ────────────────────────────────────────────────────────────

echo
echo "--- 5. gcloud destructive commands blocked"

assert_exit "5.1 gcloud compute instances delete blocks" 2 \
	"$(make_input 'gcloud compute instances delete my-vm')"
assert_exit "5.2 gcloud projects destroy blocks" 2 \
	"$(make_input 'gcloud projects destroy my-project')"
assert_exit "5.3 gcloud iam roles disable blocks" 2 \
	"$(make_input 'gcloud iam roles disable my-role')"

# ── 6. gcloud allow ───────────────────────────────────────────────────────────

echo
echo "--- 6. gcloud safe commands pass"

assert_exit "6.1 gcloud config list passes" 0 "$(make_input 'gcloud config list')"
assert_exit "6.2 gcloud projects list passes" 0 "$(make_input 'gcloud projects list')"

# ── 7. uv deny ────────────────────────────────────────────────────────────────

echo
echo "--- 7. uv destructive commands blocked"

assert_exit "7.1 uv pip uninstall blocks" 2 "$(make_input 'uv pip uninstall requests')"
assert_exit "7.2 uv cache clean blocks" 2 "$(make_input 'uv cache clean')"
assert_exit "7.3 uv tool uninstall blocks" 2 "$(make_input 'uv tool uninstall ruff')"

# ── 8. uv allow ───────────────────────────────────────────────────────────────

echo
echo "--- 8. uv safe commands pass"

assert_exit "8.1 uv run passes" 0 "$(make_input 'uv run python script.py')"
assert_exit "8.2 uv pip install passes" 0 "$(make_input 'uv pip install requests')"
assert_exit "8.3 uv pip list passes" 0 "$(make_input 'uv pip list')"

# ── 9. No command field passes through ────────────────────────────────────────

echo
echo "--- 9. No command field is a no-op"

assert_exit "9.1 empty command field passes" 0 \
	'{"tool_name":"Bash","tool_input":{"command":""}}'
assert_exit "9.2 missing command field passes" 0 \
	'{"tool_name":"Bash","tool_input":{}}'

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
