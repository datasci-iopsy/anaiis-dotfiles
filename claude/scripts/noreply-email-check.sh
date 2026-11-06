#!/usr/bin/env bash
# noreply-email-check.sh -- reject a commit identity that is not a GitHub noreply address.
#
# Opt-in: runs only in a repo whose root holds the file .require-noreply-email.
# Elsewhere it exits 0, so a work repo keeps its work address.
#
# Modes:
#   staged  (repo-pre-commit.sh) checks the identity that the next commit uses:
#           git var GIT_AUTHOR_IDENT and GIT_COMMITTER_IDENT. These read the
#           environment, the -c options, and the config.
#   push    (repo-pre-push.sh) reads git's pre-push lines on stdin and checks the
#           author and committer email of every commit that the push sends. This
#           also covers commits that never ran pre-commit: --no-verify, merges,
#           rebases, and cherry-picks.
#
# Accepted: <id>+<login>@users.noreply.github.com, <login>@users.noreply.github.com
# (a [bot] suffix allowed), and noreply@github.com (commits made on GitHub).
#
# Bypass: SKIP_EMAIL_CHECK=1. Known limit: git commit --no-verify and git push
# --no-verify skip this check.
#
# Runs under git, outside the harness bash pin, so it stays bash 3.2-safe.

set -euo pipefail

MODE="${1:-}"
[ "${SKIP_EMAIL_CHECK:-0}" = "1" ] && exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$ROOT/.require-noreply-email" ] || exit 0

NOREPLY_RE='^([0-9]+\+)?[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?@users\.noreply\.github\.com$'
bad=0

check() { # <what> <address>: report the address and set bad=1 when it is not noreply
	[ "$2" = "noreply@github.com" ] && return 0
	[[ "$2" =~ $NOREPLY_RE ]] && return 0
	printf 'noreply-email-check: %s uses "%s", which is not a GitHub noreply address.\n' "$1" "$2" >&2
	bad=1
}

case "$MODE" in
	staged)
		for field in GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT; do
			# An unknown identity gives an empty email, which check rejects.
			email="$(git var "$field" 2>/dev/null || true)"
			email="${email#*<}"
			check "the next commit's $field" "${email%%>*}"
		done
		;;
	push)
		ZERO_SHA=0000000000000000000000000000000000000000
		while read -r _local_ref local_sha _remote_ref remote_sha; do
			case "$local_sha" in "" | "$ZERO_SHA") continue ;; esac
			# Skip what the remote has: its old tip when this clone holds it, else every remote ref.
			known=--remotes
			if [ "$remote_sha" != "$ZERO_SHA" ] && git cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
				known="$remote_sha"
			fi
			commits="$(git log --format='%H %ae %ce' "$local_sha" --not "$known")"
			while read -r sha ae ce; do
				[ -n "$sha" ] || continue
				check "commit ${sha:0:12} (author)" "$ae"
				check "commit ${sha:0:12} (committer)" "$ce"
			done <<EOF
$commits
EOF
		done
		;;
	*)
		echo "Usage: noreply-email-check.sh <staged|push>" >&2
		exit 2
		;;
esac

if [ "$bad" -eq 1 ]; then
	printf 'This repo requires one (.require-noreply-email). Fix the identity:\n' >&2
	printf '  git config user.email <id>+<login>@users.noreply.github.com\n' >&2
	if [ "$MODE" = staged ]; then
		# Git did not make this commit, so --amend would change the previous commit.
		printf 'Then run git commit again.\n' >&2
	else
		printf 'Then redo each commit listed above. For the last commit:\n' >&2
		printf '  git commit --amend --reset-author --no-edit\n' >&2
	fi
	printf 'Bypass for one command (owner only): SKIP_EMAIL_CHECK=1\n' >&2
fi
exit "$bad"
