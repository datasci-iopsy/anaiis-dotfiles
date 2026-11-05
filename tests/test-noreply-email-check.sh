#!/usr/bin/env bash
# tests/test-noreply-email-check.sh -- the noreply email guard (issue 40).
#
# Contract: in a repo whose root holds .require-noreply-email, the pre-commit
# dispatcher rejects a commit whose author or committer email is not a GitHub
# noreply address, and the pre-push dispatcher rejects a push that sends such a
# commit, before the test suite runs. A repo without the marker is not checked.
# SKIP_EMAIL_CHECK=1 bypasses both.
#
# Why: on 2026-11-05 a commit with a private address reached `git push`, and
# GitHub's GH007 caught it only at the server. GH007 does not know a work email,
# so a work email would have been published.
#
# Hermetic: HOME points at a throwaway tree whose ~/.claude links into this
# checkout (tests/lib/fresh-home.sh). The real installer puts the shims into
# throwaway repos, and every commit below runs through them. The ambient
# GIT_AUTHOR_* and GIT_COMMITTER_* variables are cleared, so each case sets the
# identity it tests.
#
# Exit 0 on full pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_DIR/claude/scripts/install-repo-hooks.sh"
PRE_PUSH="$REPO_DIR/claude/hooks/repo-pre-push.sh"

PASS=0
FAIL=0

assert_eq() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/fresh-home.sh
. "$REPO_DIR/tests/lib/fresh-home.sh"
TMP_HOME="$(TMPDIR="$WORK" fresh_home_new "$REPO_DIR")"

unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
	GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE SKIP_EMAIL_CHECK 2>/dev/null || true

NR='123456+octo@users.noreply.github.com'
NR2='octo@users.noreply.github.com'
BAD='a@example.com'
ZERO=0000000000000000000000000000000000000000

# make_repo <dir> <marker 0|1>: a repo with a noreply identity in its config, a
# stub tests/run-all.sh that drops .suite-ran, one initial commit, and the
# shims from the real installer.
make_repo() {
	local dir="$1" marker="$2"
	mkdir -p "$dir/tests"
	git -C "$dir" init -q -b main
	git -C "$dir" config user.name "Octo"
	git -C "$dir" config user.email "$NR"
	# shellcheck disable=SC2016 # $(...) stays literal: it is the text of the stub script
	printf '#!/usr/bin/env bash\ntouch "$(git rev-parse --show-toplevel)/.suite-ran"\n' >"$dir/tests/run-all.sh"
	git -C "$dir" add tests/run-all.sh
	if [ "$marker" = 1 ]; then
		printf '# opt-in marker for claude/scripts/noreply-email-check.sh\n' >"$dir/.require-noreply-email"
		git -C "$dir" add .require-noreply-email
	fi
	git -C "$dir" commit -q -m init
	(cd "$dir" && HOME="$TMP_HOME" bash "$INSTALLER" >/dev/null 2>&1)
}

# try_commit <dir> <command...>: run the command in <dir> with the throwaway
# HOME; print "accepted" when HEAD moved, "rejected" when it did not.
try_commit() {
	local dir="$1" before after
	shift
	before="$(git -C "$dir" rev-parse HEAD)"
	(cd "$dir" && env HOME="$TMP_HOME" "$@") >"$WORK/last.out" 2>&1
	after="$(git -C "$dir" rev-parse HEAD)"
	if [ "$before" = "$after" ]; then echo rejected; else echo accepted; fi
}

# run_push <dir> <stdin lines>: call the pre-push dispatcher the way git does;
# print its exit status. Output goes to $WORK/last.out.
run_push() {
	local dir="$1" lines="$2"
	rm -f "$dir/.suite-ran"
	(cd "$dir" && printf '%s\n' "$lines" | HOME="$TMP_HOME" bash "$PRE_PUSH" origin url) >"$WORK/last.out" 2>&1
	echo "$?"
}

R="$WORK/marked"
make_repo "$R" 1
N="$WORK/unmarked"
make_repo "$N" 0

echo "=== 1. author email at commit time ==="
assert_eq "1.1 a private author email is rejected" rejected \
	"$(try_commit "$R" GIT_AUTHOR_EMAIL="$BAD" git commit -q --allow-empty -m c11)"
assert_eq "1.2 the message names the address" 1 "$(grep -cF -- "$BAD" "$WORK/last.out")"
assert_eq "1.3 the message gives the fix" 1 "$(grep -c 'git config user.email' "$WORK/last.out")"
assert_eq "1.4 the <id>+<login> noreply shape is accepted" accepted \
	"$(try_commit "$R" GIT_AUTHOR_EMAIL="$NR" git commit -q --allow-empty -m c14)"
assert_eq "1.5 the <login> noreply shape is accepted" accepted \
	"$(try_commit "$R" GIT_AUTHOR_EMAIL="$NR2" GIT_COMMITTER_EMAIL="$NR2" git commit -q --allow-empty -m c15)"
assert_eq "1.6 a bot noreply address is accepted" accepted \
	"$(try_commit "$R" GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' git commit -q --allow-empty -m c16)"
assert_eq "1.7 a look-alike domain is rejected" rejected \
	"$(try_commit "$R" GIT_AUTHOR_EMAIL='octo@users.noreply.github.com.evil.io' git commit -q --allow-empty -m c17)"
# Pre-commit refused the commit, so --amend would fold the next change into the previous commit.
assert_eq "1.8 a staged reject does not give the --amend hint" 0 "$(grep -c -- '--amend' "$WORK/last.out")"

echo "=== 2. committer email at commit time ==="
assert_eq "2.1 a private committer email with a noreply author is rejected" rejected \
	"$(try_commit "$R" GIT_COMMITTER_EMAIL="$BAD" git commit -q --allow-empty -m c21)"

echo "=== 3. config override on the command line ==="
assert_eq "3.1 git -c user.email=<private> is rejected" rejected \
	"$(try_commit "$R" git -c user.email="$BAD" commit -q --allow-empty -m c31)"

echo "=== 4. --author: what pre-commit sees, and the push backstop ==="
SEEN="$(try_commit "$R" git commit -q --allow-empty --author="A <$BAD>" -m c41)"
printf '  INFO  4.0 pre-commit result for --author with a private email: %s\n' "$SEEN"
if [ "$SEEN" = rejected ]; then
	try_commit "$R" SKIP_EMAIL_CHECK=1 git commit -q --allow-empty --author="A <$BAD>" -m c41b >/dev/null
fi
assert_eq "4.1 the commit with the private --author exists for the push case" "$BAD" "$(git -C "$R" log -1 --format=%ae)"
PARENT="$(git -C "$R" rev-parse HEAD~1)"
HEAD_SHA="$(git -C "$R" rev-parse HEAD)"
assert_eq "4.2 push mode rejects the --author commit" 1 \
	"$(run_push "$R" "refs/heads/main $HEAD_SHA refs/heads/main $PARENT")"
assert_eq "4.3 the suite does not run after a reject" 0 "$([ -e "$R/.suite-ran" ] && echo 1 || echo 0)"
git -C "$R" reset -q --hard "$PARENT"

echo "=== 5. amend with a private identity ==="
assert_eq "5.1 --amend --reset-author with a private email is rejected" rejected \
	"$(try_commit "$R" git -c user.email="$BAD" commit -q --amend --allow-empty --reset-author --no-edit)"

echo "=== 6. a repo without the marker ==="
assert_eq "6.1 a private email is accepted where the repo has no marker" accepted \
	"$(try_commit "$N" GIT_AUTHOR_EMAIL='test@test.com' GIT_COMMITTER_EMAIL='test@test.com' git commit -q --allow-empty -m c61)"
NHEAD="$(git -C "$N" rev-parse HEAD)"
NPARENT="$(git -C "$N" rev-parse HEAD~1)"
assert_eq "6.2 push mode ignores a repo without the marker" 0 \
	"$(run_push "$N" "refs/heads/main $NHEAD refs/heads/main $NPARENT")"

echo "=== 7. bypass ==="
assert_eq "7.1 SKIP_EMAIL_CHECK=1 accepts a private email" accepted \
	"$(try_commit "$R" SKIP_EMAIL_CHECK=1 GIT_AUTHOR_EMAIL="$BAD" git commit -q --allow-empty -m c71)"
git -C "$R" reset -q --hard HEAD~1

echo "=== 8. push mode ==="
BASE="$(git -C "$R" rev-parse HEAD)"
try_commit "$R" SKIP_EMAIL_CHECK=1 GIT_AUTHOR_EMAIL="$BAD" git commit -q --allow-empty -m c81 >/dev/null
BADSHA="$(git -C "$R" rev-parse HEAD)"
try_commit "$R" git commit -q --allow-empty -m c82 >/dev/null
TOP="$(git -C "$R" rev-parse HEAD)"
assert_eq "8.1 a range that holds one private-email commit is rejected" 1 \
	"$(run_push "$R" "refs/heads/main $TOP refs/heads/main $BASE")"
assert_eq "8.2 the reject message names the address" 1 "$(grep -cF -- "$BAD" "$WORK/last.out")"
assert_eq "8.3 a deletion line alone is skipped" 0 \
	"$(run_push "$R" "(delete) $ZERO refs/heads/old $BADSHA")"
git -C "$R" update-ref refs/remotes/origin/main "$BADSHA"
assert_eq "8.4 a new branch checks only commits that no remote ref holds" 0 \
	"$(run_push "$R" "refs/heads/topic $TOP refs/heads/topic $ZERO")"
assert_eq "8.5 the suite still runs after a clean check" 1 "$([ -e "$R/.suite-ran" ] && echo 1 || echo 0)"
git -C "$R" update-ref -d refs/remotes/origin/main
assert_eq "8.6 a new branch with an unpushed private-email commit is rejected" 1 \
	"$(run_push "$R" "refs/heads/topic $TOP refs/heads/topic $ZERO")"
git -C "$R" update-ref refs/remotes/origin/main "$BASE"
assert_eq "8.7 a remote sha that the clone lacks falls back to the remote refs" 1 \
	"$(run_push "$R" "refs/heads/main $TOP refs/heads/main 1111111111111111111111111111111111111111")"
assert_eq "8.8 a push reject gives the --amend hint for the listed commits" 1 "$(grep -c -- '--amend' "$WORK/last.out")"
git -C "$R" update-ref refs/remotes/origin/main "$BADSHA"
assert_eq "8.7b the fallback leaves out a private-email commit that a remote ref holds" 0 \
	"$(run_push "$R" "refs/heads/main $TOP refs/heads/main 1111111111111111111111111111111111111111")"
git -C "$R" update-ref -d refs/remotes/origin/main

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
