#!/usr/bin/env bash
# tests/test-public-tree.sh -- the tracked tree holds nothing that must not go public.
#
# Why: the repo is public. A tracked file must not name the old personal repo, a private email
# address, or the employer. This suite scans the tracked files with git grep and proves that each
# scanner reports a planted hit (section 0).
#
# Employer terms never enter a tracked file. They come from an untracked file, one term per line,
# matched as fixed strings without case. When the file is absent (CI), case 3 prints SKIP. A hit
# prints only the file path and the line number, never the term.
#
# Usage: bash tests/test-public-tree.sh
#        EMPLOYER_TERMS_FILE=/path/to/terms.txt bash tests/test-public-tree.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMS_FILE="${EMPLOYER_TERMS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/anaiis-dotfiles/employer-terms.txt}"

# This file lists the old repo and a planted address, so cases 1 and 2 skip it.
SELF='tests/test-public-tree.sh'

PASS=0
FAIL=0

assert_eq() {
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

OLD_REPO='datasci-iopsy/anaiis-dotfiles'

# An address needs a dotted domain, so eval@local, t@t, and plugin@marketplace are not addresses.
# The brackets let a [bot] login reach the allowlist.
EMAIL_RE='[][A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

# One extended regular expression per line. Each must match the whole address.
# n@<name>.md: the n of a \n escape before an @<name>.md import line, not an address. A test writes
# one. The entry is a pattern: the test that guards a removed tool forbids its name here.
# octo@...evil.io: the look-alike fixture of the email guard test, kept exact on purpose.
EMAIL_ALLOW='([0-9]+\+)?[A-Za-z0-9-]+(\[bot\])?@users\.noreply\.github\.com
noreply@github\.com
git@github\.com
[^@]+@example\.com
test@test\.com
t@t\.com
octo@users\.noreply\.github\.com\.evil\.io
n@[A-Za-z0-9_-]+\.md'

# old_repo_hits <repo_dir>: print "<file>:<line>" for each tracked line that names the old repo.
old_repo_hits() {
	git -C "$1" grep -I -n -i -F -e "$OLD_REPO" -- . ":(exclude)$SELF" | cut -d: -f1,2
}

# email_hits <repo_dir>: print "<file>:<line>:<address>" for each address outside the allowlist.
# sed anchors each allowlist pattern to the address field, so a pattern must match the whole address.
email_hits() {
	git -C "$1" grep -I -n -o -E -e "$EMAIL_RE" -- . ":(exclude)$SELF" \
		| grep -vE -f <(printf '%s\n' "$EMAIL_ALLOW" | sed 's/.*/^[^:]*:[0-9]+:(&)$/')
}

# employer_hits <repo_dir> <terms_file>: print "<file>:<line>" for each tracked line that holds a
# term. Lines of only spaces in the terms file are dropped: " " would match most lines.
# cut drops the line text, so the term never reaches the output.
employer_hits() {
	grep -v '^[[:space:]]*$' "$2" | git -C "$1" grep -I -n -i -F -f - | cut -d: -f1,2
}

# ── 0. Each scanner reports a planted hit (fail-to-fail) ───────────────────
echo "# 0. Each scanner reports a planted hit"
FIX="$(mktemp -d "${TMPDIR:-/tmp}/test-public-tree.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
git init -q --template= "$FIX"
printf '%s\n' \
	'git clone git@github.com:org/repo.git' \
	'author 123456+octo@users.noreply.github.com' \
	'bot 41898282+github-actions[bot]@users.noreply.github.com' \
	'mail noreply@github.com and ana@example.com' \
	"printf 'imports\\n@NOTES.md\\n'" \
	'plugin ponytail@ponytail, commit as eval@local' >"$FIX/ok.txt"
printf '%s\n' 'clean line' 'contact jane.doe@corp-internal.com' \
	'look-alike x@users.noreply.github.com.evil.io' >"$FIX/bad.txt"
git -C "$FIX" add ok.txt bad.txt
assert_eq "0.1 an address outside the allowlist is reported, and allowed shapes are quiet" \
	"bad.txt:2:jane.doe@corp-internal.com
bad.txt:3:x@users.noreply.github.com.evil.io" "$(email_hits "$FIX")"

printf '%s\n' 'first line' 'we built this at ZZ-Fake-Employer last year' >"$FIX/notes.txt"
git -C "$FIX" add notes.txt
printf '\n \nzz-fake-employer\n\n' >"$FIX/terms.txt"
OUT="$(employer_hits "$FIX" "$FIX/terms.txt")"
assert_eq "0.2 a term is found without case, and a blank terms line matches nothing" "notes.txt:2" "$OUT"
assert_eq "0.3 the hit output does not hold the term" 0 "$(printf '%s\n' "$OUT" | grep -ci 'fake-employer')"

printf '%s\n' 'old home: github.com/DataSci-IOPSY/Anaiis-Dotfiles' >"$FIX/repo.txt"
git -C "$FIX" add repo.txt
assert_eq "0.4 a mention of the old repo is found without case" "repo.txt:1" "$(old_repo_hits "$FIX")"

# ── 1. The old repo is not named ───────────────────────────────────────────
echo "# 1. No tracked file names the old repo"
assert_eq "1.1 no tracked file holds $OLD_REPO" "" "$(old_repo_hits "$REPO_DIR")"

# ── 2. Only allowed email addresses ────────────────────────────────────────
echo "# 2. No tracked file holds an email address outside the allowlist"
assert_eq "2.1 every tracked address is on the allowlist" "" "$(email_hits "$REPO_DIR")"

# ── 3. No employer term ────────────────────────────────────────────────────
echo "# 3. No tracked file holds an employer term"
if grep -q '[^[:space:]]' "$TERMS_FILE" 2>/dev/null; then
	assert_eq "3.1 no tracked file holds a term from the terms file" "" "$(employer_hits "$REPO_DIR" "$TERMS_FILE")"
else
	printf '  SKIP  3.1 terms file absent or empty: %s\n' "$TERMS_FILE"
fi

# ── 4. The license files are in place ──────────────────────────────────────
# LICENSE is the Apache-2.0 text as GitHub publishes it. NOTICE carries the attribution that
# section 4(d) makes a redistributor keep, with the holder filled in.
echo "# 4. The license files are in place"
assert_eq "4.1 LICENSE starts with the Apache License title" "Apache License" \
	"$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}' "$REPO_DIR/LICENSE" 2>/dev/null)"
assert_eq "4.2 LICENSE names Version 2.0, January 2004" 1 \
	"$(grep -c 'Version 2\.0, January 2004' "$REPO_DIR/LICENSE" 2>/dev/null)"
assert_eq "4.3 NOTICE holds one copyright line for the holder" "Copyright 2026 Anaiis LLC" \
	"$(grep '^Copyright ' "$REPO_DIR/NOTICE" 2>/dev/null)"
assert_eq "4.4 NOTICE holds no placeholder" 0 "$(grep -c '[][<>]' "$REPO_DIR/NOTICE" 2>/dev/null || true)"
assert_eq "4.5 README.md has a License section that excludes the plugins" "yes" \
	"$(sed -n '/^## License$/,/^## /p' "$REPO_DIR/README.md" | grep -q 'anaiis-plugins' && echo yes || echo no)"

printf '\ntest-public-tree: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
