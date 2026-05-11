#!/usr/bin/env bash
# tests/test-staged-lint-dispatch.sh
#
# Verifies the five staged-lint scripts: clean passes, dirty blocks,
# SKIP_* bypasses, no staged files exits 0, missing tool exits 0.
#
# Exits 0 on full pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_DIR/claude/scripts"
FIXTURES="$REPO_DIR/tests/fixtures/post-edit-lint"

PASS=0
FAIL=0
WORK=""

cleanup() {
	[ -n "$WORK" ] && rm -rf "$WORK"
}
trap cleanup EXIT

WORK=$(mktemp -d)

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

# Create a disposable git repo, stage the given file, run the given script,
# return its exit code; output (stdout+stderr) captured to $RUN_OUTPUT.
RUN_OUTPUT=""
run_staged() {
	local script="$1" src="$2" dest_name="$3"
	local repo
	repo=$(mktemp -d "$WORK/repo.XXXXXX")
	git -C "$repo" init -q
	git -C "$repo" config user.email "test@test.com"
	git -C "$repo" config user.name "Test"
	cp "$src" "$repo/$dest_name"
	git -C "$repo" add "$dest_name"
	(cd "$repo" && bash "$script") >"$WORK/run.out" 2>&1
	local rc=$?
	RUN_OUTPUT=$(cat "$WORK/run.out")
	return $rc
}

# Run the script in a repo with no staged files of that type.
run_empty() {
	local script="$1"
	local repo
	repo=$(mktemp -d "$WORK/empty.XXXXXX")
	git -C "$repo" init -q
	(cd "$repo" && bash "$script") >"$WORK/run.out" 2>&1
	local rc=$?
	RUN_OUTPUT=$(cat "$WORK/run.out")
	return $rc
}

# ── sqlfmt ───────────────────────────────────────────────────────────────────
echo "# sqlfmt staged-lint"

SQLFMT_SCRIPT="$SCRIPTS/sqlfmt-lint-staged.sh"
[ -f "$SQLFMT_SCRIPT" ] \
	&& {
		PASS=$((PASS + 1))
		echo "  PASS  sqlfmt.0 script exists"
	} \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  sqlfmt.0 script missing: $SQLFMT_SCRIPT"
	}

SQLFMT=""
command -v sqlfmt &>/dev/null && SQLFMT="sqlfmt"
[[ -z "$SQLFMT" && -x "$HOME/.local/bin/sqlfmt" ]] && SQLFMT="$HOME/.local/bin/sqlfmt"

if [[ -n "$SQLFMT" ]]; then
	# Clean file passes
	CLEAN_SQL=$(mktemp "$WORK/clean.XXXXXX.sql")
	printf 'select id, name from users\n' >"$CLEAN_SQL"
	$SQLFMT --line-length 120 "$CLEAN_SQL" &>/dev/null
	run_staged "$SQLFMT_SCRIPT" "$CLEAN_SQL" "clean.sql"
	assert_exit "sqlfmt.1 clean file exits 0" "0" "$?"
	assert_contains "sqlfmt.2 clean prints No issues" "No issues found" "$RUN_OUTPUT"

	# Dirty file blocks
	DIRTY_SQL=$(mktemp "$WORK/dirty.XXXXXX.sql")
	printf 'SELECT ID,NAME FROM USERS\n' >"$DIRTY_SQL"
	run_staged "$SQLFMT_SCRIPT" "$DIRTY_SQL" "dirty.sql"
	assert_exit "sqlfmt.3 dirty file exits 1" "1" "$?"
	assert_contains "sqlfmt.4 dirty prints fix hint" "SKIP_SQLFMT" "$RUN_OUTPUT"

	# SKIP_SQLFMT=1 bypasses
	DIRTY_SQL2=$(mktemp "$WORK/dirty2.XXXXXX.sql")
	printf 'SELECT ID,NAME FROM USERS\n' >"$DIRTY_SQL2"
	local_repo=$(mktemp -d "$WORK/skip.XXXXXX")
	git -C "$local_repo" init -q
	cp "$DIRTY_SQL2" "$local_repo/dirty.sql"
	git -C "$local_repo" add dirty.sql
	(cd "$local_repo" && SKIP_SQLFMT=1 bash "$SQLFMT_SCRIPT") >"$WORK/run.out" 2>&1
	assert_exit "sqlfmt.5 SKIP_SQLFMT=1 exits 0" "0" "$?"
else
	echo "  SKIP  sqlfmt.1-5 sqlfmt not installed"
fi

# No staged SQL files exits 0
run_empty "$SQLFMT_SCRIPT"
assert_exit "sqlfmt.6 no staged SQL exits 0" "0" "$?"

# Missing tool exits 0 with notice
DIRTY_SQL3=$(mktemp "$WORK/missing.XXXXXX.sql")
printf 'SELECT ID FROM USERS\n' >"$DIRTY_SQL3"
repo=$(mktemp -d "$WORK/miss.XXXXXX")
git -C "$repo" init -q
cp "$DIRTY_SQL3" "$repo/dirty.sql"
git -C "$repo" add dirty.sql
(cd "$repo" && PATH=/dev/null bash "$SQLFMT_SCRIPT") >"$WORK/run.out" 2>&1
RUN_OUTPUT=$(cat "$WORK/run.out")
assert_exit "sqlfmt.7 missing tool exits 0" "0" "$?"
assert_contains "sqlfmt.8 missing tool prints notice" "not found" "$RUN_OUTPUT"

# ── shfmt ────────────────────────────────────────────────────────────────────
echo "# shfmt staged-lint"

SHFMT_SCRIPT="$SCRIPTS/shfmt-lint-staged.sh"

if command -v shfmt &>/dev/null; then
	CLEAN_SH=$(mktemp "$WORK/clean.XXXXXX.sh")
	printf '#!/usr/bin/env bash\necho hello\n' >"$CLEAN_SH"
	shfmt -w -i 0 -bn -ci "$CLEAN_SH" &>/dev/null
	run_staged "$SHFMT_SCRIPT" "$CLEAN_SH" "clean.sh"
	assert_exit "shfmt.1 clean file exits 0" "0" "$?"

	DIRTY_SH=$(mktemp "$WORK/dirty.XXXXXX.sh")
	printf '#!/usr/bin/env bash\nif [ 1 ]; then\n  echo bad\n  fi\n' >"$DIRTY_SH"
	run_staged "$SHFMT_SCRIPT" "$DIRTY_SH" "dirty.sh"
	assert_exit "shfmt.2 dirty file exits 1" "1" "$?"
	assert_contains "shfmt.3 dirty prints SKIP_SHFMT" "SKIP_SHFMT" "$RUN_OUTPUT"
else
	echo "  SKIP  shfmt.1-3 shfmt not installed"
fi

run_empty "$SHFMT_SCRIPT"
assert_exit "shfmt.4 no staged sh exits 0" "0" "$?"

# ── ruff ─────────────────────────────────────────────────────────────────────
echo "# ruff staged-lint"

RUFF_SCRIPT="$SCRIPTS/ruff-lint-staged.sh"
RUFF=""
command -v ruff &>/dev/null && RUFF="ruff"
[[ -z "$RUFF" && -x "$HOME/.local/bin/ruff" ]] && RUFF="$HOME/.local/bin/ruff"

if [[ -n "$RUFF" ]]; then
	CLEAN_PY=$(mktemp "$WORK/clean.XXXXXX.py")
	printf 'x = 1\ny = 2\n' >"$CLEAN_PY"
	run_staged "$RUFF_SCRIPT" "$CLEAN_PY" "clean.py"
	assert_exit "ruff.1 clean file exits 0" "0" "$?"

	DIRTY_PY=$(mktemp "$WORK/dirty.XXXXXX.py")
	printf 'x=1\ny =  2\n' >"$DIRTY_PY"
	run_staged "$RUFF_SCRIPT" "$DIRTY_PY" "dirty.py"
	assert_exit "ruff.2 dirty file exits 1" "1" "$?"
	assert_contains "ruff.3 dirty prints SKIP_RUFF" "SKIP_RUFF" "$RUN_OUTPUT"
else
	echo "  SKIP  ruff.1-3 ruff not installed"
fi

run_empty "$RUFF_SCRIPT"
assert_exit "ruff.4 no staged py exits 0" "0" "$?"

# ── json ─────────────────────────────────────────────────────────────────────
echo "# json staged-lint"

JSON_SCRIPT="$SCRIPTS/json-lint-staged.sh"

if command -v jq &>/dev/null; then
	CLEAN_JSON=$(mktemp "$WORK/clean.XXXXXX.json")
	printf '{\n    "a": 1\n}\n' >"$CLEAN_JSON"
	run_staged "$JSON_SCRIPT" "$CLEAN_JSON" "clean.json"
	assert_exit "json.1 clean file exits 0" "0" "$?"

	DIRTY_JSON=$(mktemp "$WORK/dirty.XXXXXX.json")
	printf '{"a":1}\n' >"$DIRTY_JSON"
	run_staged "$JSON_SCRIPT" "$DIRTY_JSON" "dirty.json"
	assert_exit "json.2 dirty file exits 1" "1" "$?"
	assert_contains "json.3 dirty prints SKIP_JSON_LINT" "SKIP_JSON_LINT" "$RUN_OUTPUT"
else
	echo "  SKIP  json.1-3 jq not installed"
fi

run_empty "$JSON_SCRIPT"
assert_exit "json.4 no staged json exits 0" "0" "$?"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
