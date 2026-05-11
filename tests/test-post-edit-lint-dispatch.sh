#!/usr/bin/env bash
# tests/test-post-edit-lint-dispatch.sh
#
# Verifies that post-edit-lint.sh correctly dispatches by file extension,
# auto-fixes deterministic formatters (json, sql, sh, py), and always exits 0.
#
# Exits 0 on full pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/post-edit-lint.sh"
FIXTURES="$REPO_DIR/tests/fixtures/post-edit-lint"

PASS=0
FAIL=0
TMPDIR_WORK=""

cleanup() {
	[ -n "$TMPDIR_WORK" ] && rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT

TMPDIR_WORK=$(mktemp -d)

assert_exit() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected exit=%s, got %s\n' \
			"$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

assert_contains() {
	local name="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected to contain: %s\n        actual:   %s\n' \
			"$name" "$needle" "$haystack"
		FAIL=$((FAIL + 1))
	fi
}

assert_not_contains() {
	local name="$1" needle="$2" haystack="$3"
	if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected NOT to contain: %s\n        actual:   %s\n' \
			"$name" "$needle" "$haystack"
		FAIL=$((FAIL + 1))
	fi
}

assert_files_equal() {
	local name="$1" expected="$2" actual="$3"
	if diff -q "$expected" "$actual" &>/dev/null; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n' "$name"
		diff "$expected" "$actual" | head -10 | sed 's/^/        /'
		FAIL=$((FAIL + 1))
	fi
}

run_hook() {
	local json="$1"
	local stderr_file
	stderr_file="$TMPDIR_WORK/hook.stderr"
	printf '%s' "$json" | bash "$HOOK" 2>"$stderr_file"
	local rc=$?
	cat "$stderr_file"
	return $rc
}

# ── 1. Hook file present and executable ──────────────────────────────────────
echo "# 1. Hook file"
[ -f "$HOOK" ] && PASS=$((PASS + 1)) && echo "  PASS  1.1 hook exists" \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  1.1 hook missing: $HOOK"
	}
[ -x "$HOOK" ] && PASS=$((PASS + 1)) && echo "  PASS  1.2 hook executable" \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  1.2 hook not executable"
	}

# ── 2. Always exits 0 ─────────────────────────────────────────────────────────
echo "# 2. Exit code always 0"
for ext in json sql sh py R; do
	tmp="$TMPDIR_WORK/test.$ext"
	cp "$FIXTURES/messy.json.in" "$tmp" 2>/dev/null || touch "$tmp"
	json="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp\"}}"
	stderr=$(run_hook "$json" 2>&1)
	assert_exit "2.1 exit=0 for .$ext" "0" "$?"
done

# ── 3. No-op for unknown extension ───────────────────────────────────────────
echo "# 3. No-op for unknown extension"
tmp="$TMPDIR_WORK/test.xyz"
touch "$tmp"
json="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp\"}}"
stderr=$(run_hook "$json" 2>&1)
assert_exit "3.1 exit=0 for .xyz" "0" "$?"
assert_not_contains "3.2 no [lint] marker for .xyz" "[lint]" "$stderr"

# ── 4. Empty file_path is a no-op ────────────────────────────────────────────
echo "# 4. Empty file_path"
json="{\"tool_name\":\"Write\",\"tool_input\":{}}"
stderr=$(run_hook "$json" 2>&1)
assert_exit "4.1 exit=0 for empty path" "0" "$?"

# ── 5. JSON auto-fix ─────────────────────────────────────────────────────────
echo "# 5. JSON auto-fix (jq --indent 4)"
if command -v jq &>/dev/null; then
	tmp="$TMPDIR_WORK/fix.json"
	cp "$FIXTURES/messy.json.in" "$tmp"
	json="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp\"}}"
	stderr=$(run_hook "$json" 2>&1)
	assert_contains "5.1 [lint] json: marker present" "[lint] json:" "$stderr"
	assert_files_equal "5.2 json output matches expected" "$FIXTURES/messy.json.expected" "$tmp"
else
	echo "  SKIP  5.x jq not installed"
fi

# ── 6. Shell auto-fix ────────────────────────────────────────────────────────
echo "# 6. Shell auto-fix (shfmt)"
if command -v shfmt &>/dev/null; then
	tmp="$TMPDIR_WORK/fix.sh"
	cp "$FIXTURES/messy.sh.in" "$tmp"
	json="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp\"}}"
	stderr=$(run_hook "$json" 2>&1)
	assert_contains "6.1 [lint] shfmt: marker present" "[lint] shfmt:" "$stderr"
	assert_files_equal "6.2 sh output matches expected" "$FIXTURES/messy.sh.expected" "$tmp"
else
	echo "  SKIP  6.x shfmt not installed"
fi

# ── 7. Python auto-fix ───────────────────────────────────────────────────────
echo "# 7. Python auto-fix (ruff format)"
RUFF=""
command -v ruff &>/dev/null && RUFF="ruff"
[[ -z "$RUFF" && -x "$HOME/.local/bin/ruff" ]] && RUFF="$HOME/.local/bin/ruff"
if [[ -n "$RUFF" ]]; then
	tmp="$TMPDIR_WORK/fix.py"
	cp "$FIXTURES/messy.py.in" "$tmp"
	json="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp\"}}"
	stderr=$(run_hook "$json" 2>&1)
	assert_contains "7.1 [lint] ruff format: marker present" "[lint] ruff format:" "$stderr"
	assert_files_equal "7.2 py output matches expected" "$FIXTURES/messy.py.expected" "$tmp"
else
	echo "  SKIP  7.x ruff not installed"
fi

# ── 8. SQL auto-fix ──────────────────────────────────────────────────────────
echo "# 8. SQL auto-fix (sqlfmt)"
SQLFMT=""
command -v sqlfmt &>/dev/null && SQLFMT="sqlfmt"
[[ -z "$SQLFMT" && -x "$HOME/.local/bin/sqlfmt" ]] && SQLFMT="$HOME/.local/bin/sqlfmt"
if [[ -n "$SQLFMT" ]]; then
	tmp="$TMPDIR_WORK/fix.sql"
	cp "$FIXTURES/messy.sql.in" "$tmp"
	json="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp\"}}"
	stderr=$(run_hook "$json" 2>&1)
	assert_contains "8.1 [lint] sqlfmt: marker present" "[lint] sqlfmt:" "$stderr"
	assert_files_equal "8.2 sql output matches expected" "$FIXTURES/messy.sql.expected" "$tmp"
else
	echo "  SKIP  8.x sqlfmt not installed"
fi

# ── 9. Missing tool: exits 0 with notice ─────────────────────────────────────
echo "# 9. Missing tool exits 0"
tmp="$TMPDIR_WORK/missing.sql"
cp "$FIXTURES/messy.sql.in" "$tmp"
json="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp\"}}"
# Use a fake HOME so the hook's ~/.local/bin/sqlfmt fallback also misses,
# while keeping standard tools (cat, jq, shfmt, ruff) accessible.
FAKE_HOME=$(mktemp -d "$TMPDIR_WORK/fakehome.XXXXXX")
SAFE_PATH="/usr/bin:/bin:/opt/homebrew/bin"
stderr=$(HOME="$FAKE_HOME" PATH="$SAFE_PATH" run_hook "$json" 2>&1)
assert_exit "9.1 exit=0 when sqlfmt missing" "0" "$?"
assert_contains "9.2 prints not found notice" "not found" "$stderr"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
