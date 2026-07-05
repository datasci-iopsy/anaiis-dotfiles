#!/usr/bin/env bash
# tests/test-stop-hook-git-check.sh -- verify stop-hook-git-check.sh
#
# Confirms: exits 0 on clean repo with no remote; exits 2 for uncommitted
# changes; exits 2 for untracked files; exits 2 for unpushed commits;
# exits 0 when up to date with remote; recursion guard exits 0 immediately;
# every blocking [git] message carries the "reply only: Ok" directive inline.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/claude/hooks/stop-hook-git-check.sh"

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
	local json="$3" dir="$4"
	local got
	got=$(
		cd "$dir" && printf '%s' "$json" | bash "$HOOK" 2>/dev/null
		echo $?
	)
	if [ "$got" = "$want" ]; then
		pass "$label"
	else
		fail "$label (got exit=$got, want $want)"
	fi
}

# Every [git] status line must carry the reply directive inline, so the
# terse-reply rule holds even in a session where rules/git.md wasn't loaded.
assert_stderr_has_reply_directive() {
	local label="$1" dir="$2" json="$3"
	local stderr_out
	stderr_out=$(cd "$dir" && printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null)
	case "$stderr_out" in
		*"reply only: Ok"*) pass "$label" ;;
		*) fail "$label (stderr missing reply directive: $stderr_out)" ;;
	esac
}

CLEAN_INPUT='{"stop_hook_active":false}'
ACTIVE_INPUT='{"stop_hook_active":true}'

# Helper: create a local repo with a bare remote and a tracking branch.
# Stdout/stderr suppressed so they don't contaminate read -r.
setup_repo_with_remote() {
	local base
	base=$(mktemp -d)
	local bare="$base/remote.git"
	local local_repo="$base/local"

	git init --bare "$bare" >/dev/null 2>&1
	git clone "$bare" "$local_repo" >/dev/null 2>&1
	(
		cd "$local_repo" \
			&& git config user.email "test@test.com" >/dev/null 2>&1 \
			&& git config user.name "Test" >/dev/null 2>&1 \
			&& printf 'init\n' >README.md \
			&& git add README.md >/dev/null 2>&1 \
			&& git commit -m "init" >/dev/null 2>&1 \
			&& git push origin HEAD >/dev/null 2>&1
	) >/dev/null 2>&1
	printf '%s' "$local_repo"
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

# ── 2. Recursion guard ────────────────────────────────────────────────────────

echo
echo "--- 2. Recursion guard exits 0 immediately"

TMP_BARE=$(mktemp -d)
git init --bare "$TMP_BARE" >/dev/null 2>&1
TMP_REPO=$(mktemp -d)
git clone "$TMP_BARE" "$TMP_REPO" >/dev/null 2>&1

got=$(
	cd "$TMP_REPO" && printf '%s' "$ACTIVE_INPUT" | bash "$HOOK" 2>/dev/null
	echo $?
)
if [ "$got" = "0" ]; then
	pass "2.1 stop_hook_active=true exits 0"
else
	fail "2.1 stop_hook_active=true should exit 0 (got $got)"
fi
rm -rf "$TMP_BARE" "$TMP_REPO"

# ── 3. No remote: exits 0 ─────────────────────────────────────────────────────

echo
echo "--- 3. Repo with no remote exits 0"

NO_REMOTE=$(mktemp -d)
(
	cd "$NO_REMOTE" \
		&& git init >/dev/null 2>&1 \
		&& git config user.email "t@t.com" >/dev/null 2>&1 \
		&& git config user.name "T" >/dev/null 2>&1 \
		&& printf 'x\n' >f.txt \
		&& git add f.txt >/dev/null 2>&1 \
		&& git commit -m "init" >/dev/null 2>&1
) >/dev/null 2>&1

got=$(
	cd "$NO_REMOTE" && printf '%s' "$CLEAN_INPUT" | bash "$HOOK" 2>/dev/null
	echo $?
)
if [ "$got" = "0" ]; then
	pass "3.1 no-remote repo exits 0"
else
	fail "3.1 no-remote repo should exit 0 (got $got)"
fi
rm -rf "$NO_REMOTE"

# ── 4. Uncommitted changes blocked ────────────────────────────────────────────

echo
echo "--- 4. Uncommitted changes blocked"

DIRTY=$(setup_repo_with_remote)

printf 'dirty\n' >>"$DIRTY/README.md"
got=$(
	cd "$DIRTY" && printf '%s' "$CLEAN_INPUT" | bash "$HOOK" 2>/dev/null
	echo $?
)
if [ "$got" = "2" ]; then
	pass "4.1 unstaged changes exit 2"
else
	fail "4.1 unstaged changes should exit 2 (got $got)"
fi
assert_stderr_has_reply_directive "4.2 uncommitted-changes message carries reply directive" "$DIRTY" "$CLEAN_INPUT"
rm -rf "$(dirname "$DIRTY")"

# ── 5. Untracked files blocked ────────────────────────────────────────────────

echo
echo "--- 5. Untracked files blocked"

UNTRACKED=$(setup_repo_with_remote)

printf 'new\n' >"$UNTRACKED/newfile.txt"
got=$(
	cd "$UNTRACKED" && printf '%s' "$CLEAN_INPUT" | bash "$HOOK" 2>/dev/null
	echo $?
)
if [ "$got" = "2" ]; then
	pass "5.1 untracked file exits 2"
else
	fail "5.1 untracked file should exit 2 (got $got)"
fi
assert_stderr_has_reply_directive "5.2 untracked-files message carries reply directive" "$UNTRACKED" "$CLEAN_INPUT"
rm -rf "$(dirname "$UNTRACKED")"

# ── 6. Unpushed commits blocked ───────────────────────────────────────────────

echo
echo "--- 6. Unpushed commits blocked"

UNPUSHED=$(setup_repo_with_remote)

(
	cd "$UNPUSHED" \
		&& git config user.email "t@t.com" >/dev/null 2>&1 \
		&& git config user.name "T" >/dev/null 2>&1 \
		&& printf 'extra\n' >extra.txt \
		&& git add extra.txt >/dev/null 2>&1 \
		&& git commit -m "unpushed" >/dev/null 2>&1
) >/dev/null 2>&1

got=$(
	cd "$UNPUSHED" && printf '%s' "$CLEAN_INPUT" | bash "$HOOK" 2>/dev/null
	echo $?
)
if [ "$got" = "2" ]; then
	pass "6.1 unpushed commit exits 2"
else
	fail "6.1 unpushed commit should exit 2 (got $got)"
fi
assert_stderr_has_reply_directive "6.2 unpushed-commits message carries reply directive" "$UNPUSHED" "$CLEAN_INPUT"
rm -rf "$(dirname "$UNPUSHED")"

# ── 7. Clean repo with remote exits 0 ────────────────────────────────────────

echo
echo "--- 7. Clean repo up-to-date with remote exits 0"

CLEAN=$(setup_repo_with_remote)

got=$(
	cd "$CLEAN" && printf '%s' "$CLEAN_INPUT" | bash "$HOOK" 2>/dev/null
	echo $?
)
if [ "$got" = "0" ]; then
	pass "7.1 clean up-to-date repo exits 0"
else
	fail "7.1 clean up-to-date repo should exit 0 (got $got)"
fi
rm -rf "$(dirname "$CLEAN")"

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
