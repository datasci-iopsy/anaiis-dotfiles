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
#           also covers --author and amended commits, which staged mode may not see.
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

is_noreply() {
	[ "$1" = "noreply@github.com" ] && return 0
	[[ "$1" =~ $NOREPLY_RE ]]
}

reject() { # <what> <address>
	printf 'noreply-email-check: %s uses "%s", which is not a GitHub noreply address.\n' "$1" "$2" >&2
	printf 'This repo requires one (.require-noreply-email). Fix the identity, then redo the commit:\n' >&2
	printf '  git config user.email <id>+<login>@users.noreply.github.com\n' >&2
	printf '  git commit --amend --reset-author --no-edit\n' >&2
	printf 'Bypass for one command (owner only): SKIP_EMAIL_CHECK=1\n' >&2
}

case "$MODE" in
	staged)
		bad=0
		for field in GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT; do
			ident="$(git var "$field" 2>/dev/null || true)"
			email="${ident#*<}"
			email="${email%%>*}"
			if [ -z "$ident" ] || ! is_noreply "$email"; then
				reject "the next commit's $field" "$email"
				bad=1
			fi
		done
		exit "$bad"
		;;
	push)
		ZERO=0000000000000000000000000000000000000000
		bad=0
		while read -r _local_ref local_sha _remote_ref remote_sha; do
			[ -n "${local_sha:-}" ] || continue
			[ "$local_sha" = "$ZERO" ] && continue
			if [ "$remote_sha" != "$ZERO" ] && git cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
				commits="$(git log --format='%H %ae %ce' "$remote_sha..$local_sha")"
			else
				commits="$(git log --format='%H %ae %ce' "$local_sha" --not --remotes)"
			fi
			while read -r sha ae ce; do
				[ -n "${sha:-}" ] || continue
				if ! is_noreply "$ae"; then
					reject "commit ${sha:0:12} (author)" "$ae"
					bad=1
				fi
				if ! is_noreply "$ce"; then
					reject "commit ${sha:0:12} (committer)" "$ce"
					bad=1
				fi
			done <<EOF
$commits
EOF
		done
		exit "$bad"
		;;
	*)
		echo "Usage: noreply-email-check.sh <staged|push>" >&2
		exit 2
		;;
esac
