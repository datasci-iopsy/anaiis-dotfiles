#!/usr/bin/env bash
# tests/test-no-stale-refs.sh -- no tracked file may name a thing that the repo removed.
#
# Why: the graphify submodule was removed on 2026-07-05, but install.sh kept a step that ran
# install-graphify.sh, and a fresh install printed a SKIP for a submodule that does not exist.
# A stale reference misleads a reader, and a stale step runs on every new machine. This suite
# keeps each removed thing gone. Each stream that removes something appends its tokens to
# DEAD_TOKENS.
#
# Same pattern as the suite that guards the other removed tool: scan the tracked files, and
# prove the scanner fails on a tree that still holds a token (section 0).
#
# Exemption: AGENTS.md and README.md still describe the removal in prose. Stream d-docs-sync owns
# both files. It rewrites them and then deletes the two names from EXEMPT_FILES.
#
# Usage: bash tests/test-no-stale-refs.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

assert() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' \
			"$name" "${expected:-<none>}" "${actual:-<none>}"
		FAIL=$((FAIL + 1))
	fi
}

# One token per line. Plain text, not a regular expression.
DEAD_TOKENS='install-graphify
vendor/graphify
graphify-venv
submodule update --init
claude/CLAUDE.md
~/.claude/CLAUDE.md
CLAUDE.local.md'

# Files that may name a dead token: this test (it lists them) and the two docs of stream d-docs-sync.
EXEMPT_FILES='tests/test-no-stale-refs.sh
AGENTS.md
README.md'

# Pairs "<file>: <token>" that may stay. The file keeps the exemption for that one token only.
# install.sh removes the old CLAUDE.md link and names the dead local files in its cleanup advice.
# The install test builds the old link, so it names the path.
EXEMPT_HITS='install.sh: claude/CLAUDE.md
install.sh: CLAUDE.local.md
tests/test-install-fresh-home.sh: claude/CLAUDE.md'

# stale_hits <repo_dir>: print "<file>: <token>" for each dead token in each tracked text file.
stale_hits() {
	local repo="$1" f tok
	while IFS= read -r -d '' f; do
		printf '%s\n' "$EXEMPT_FILES" | grep -qxF -- "$f" && continue
		while IFS= read -r tok; do
			grep -IqF -- "$tok" "$repo/$f" 2>/dev/null || continue
			printf '%s\n' "$EXEMPT_HITS" | grep -qxF -- "$f: $tok" && continue
			printf '%s: %s\n' "$f" "$tok"
		done <<EOF
$DEAD_TOKENS
EOF
	done < <(git -C "$repo" ls-files -z)
}

# ── 0. The scanner catches what it guards (fail-to-fail) ───────────────────
echo "# 0. The scanner fails on a tree that still holds a dead token"
FIX="$(mktemp -d "${TMPDIR:-/tmp}/test-no-stale-refs.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
git init -q --template= "$FIX"
printf 'bash claude/scripts/install-graphify.sh\n' >"$FIX/install.sh"
printf 'clean line\n' >"$FIX/clean.sh"
printf 'see vendor/graphify\n' >"$FIX/AGENTS.md"
git -C "$FIX" add install.sh clean.sh AGENTS.md
assert "0.1 scanner flags a token in a tracked file" "install.sh: install-graphify" "$(stale_hits "$FIX")"
git -C "$FIX" rm -q -f --cached install.sh
assert "0.2 scanner passes when only a clean file and an exempt file remain" "" "$(stale_hits "$FIX")"
printf 'git submodule update --init vendor/graphify\n' >"$FIX/clean.sh"
assert "0.3 scanner reports each token on a line separately" \
	"clean.sh: vendor/graphify
clean.sh: submodule update --init" "$(stale_hits "$FIX")"
# An exemption names one file and one token. The same token in another file, and another token in
# the same file, must still be flagged.
FIX2="$(mktemp -d "${TMPDIR:-/tmp}/test-no-stale-refs.XXXXXX")"
trap 'rm -rf "$FIX" "$FIX2"' EXIT
git init -q --template= "$FIX2"
printf 'rm /home/u/.claude/CLAUDE.md\n' >"$FIX2/install.sh"
printf 'rm /home/u/.claude/CLAUDE.md\n' >"$FIX2/other.sh"
git -C "$FIX2" add install.sh other.sh
assert "0.4 an exempt pair is quiet and the same token in another file is flagged" \
	"other.sh: claude/CLAUDE.md" "$(stale_hits "$FIX2")"
printf 'bash install-graphify.sh\nsee ~/.claude/CLAUDE.md\n' >>"$FIX2/install.sh"
assert "0.5 an exemption does not cover another token in the same file" \
	"install.sh: install-graphify
install.sh: ~/.claude/CLAUDE.md
other.sh: claude/CLAUDE.md" "$(stale_hits "$FIX2")"

# ── 1. The graphify step is gone ───────────────────────────────────────────
echo "# 1. The graphify step is gone"
assert "1.1 .gitmodules is not tracked" "" "$(git -C "$REPO_DIR" ls-files .gitmodules)"
assert "1.2 install-graphify.sh is not tracked" "" "$(git -C "$REPO_DIR" ls-files claude/scripts/install-graphify.sh)"
assert "1.3 install.sh does not name graphify" 0 "$(grep -ci graphify "$REPO_DIR/install.sh")"
assert "1.4 .gitignore does not name graphify" 0 "$(grep -ci graphify "$REPO_DIR/.gitignore")"

# ── 2. No tracked file names a dead token ──────────────────────────────────
echo "# 2. No tracked file names a dead token"
assert "2.1 no tracked file holds a dead token" "" "$(stale_hits "$REPO_DIR")"

printf '\ntest-no-stale-refs: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
