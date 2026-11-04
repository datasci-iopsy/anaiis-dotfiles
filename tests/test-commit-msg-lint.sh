#!/usr/bin/env bash
# tests/test-commit-msg-lint.sh -- the commit message validator
# (claude/scripts/commit-msg-lint.sh) and its rubric.
#
# Contract under test (rules R0 to R11, exemptions, --types): see
# claude/rules/git.md. Every rule has at least one passing and one failing
# fixture. A failing fixture states the exact set of rules it must trigger, so
# a rule that stops firing turns its fixture into a pass and fails the test.
#
# The validator runs under the same bash as this test ($BASH), so
# `/bin/bash tests/test-commit-msg-lint.sh` checks it on bash 3.2.
#
# Exit 0 on full pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="${LINT_UNDER_TEST:-$REPO_DIR/claude/scripts/commit-msg-lint.sh}"

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

# Opt-in line coverage: COV=1 bash tests/test-commit-msg-lint.sh (needs bash 4.1 or later).
if [ -n "${COV:-}" ]; then
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$WORK/cov.log"
fi

# run_lint <message>: write the message and a final newline to a file, run the
# validator on it. Sets LINT_RC (exit code) and LINT_ERR (stderr).
run_lint() {
	printf '%s\n' "$1" >"$WORK/msg"
	LINT_ERR=$("$BASH" "$LINT" "$WORK/msg" 2>&1 >/dev/null)
	LINT_RC=$?
}

# rules_hit: the unique rule ids in LINT_ERR, in numeric order, joined by spaces.
rules_hit() {
	printf '%s\n' "$LINT_ERR" | sed -n 's/^commit-msg-lint: \(R[0-9]*\) .*/\1/p' | sort -t R -k 2,2n -u | tr '\n' ' ' | sed 's/ $//'
}

# expect_pass <name> <message>: exit 0 and no rule text.
expect_pass() {
	run_lint "$2"
	assert_eq "$1" "0 " "$LINT_RC $(rules_hit)"
}

# expect_fail <name> <rules> <message>: exit 1 and exactly these rules.
expect_fail() {
	run_lint "$3"
	assert_eq "$1" "1 $2" "$LINT_RC $(rules_hit)"
}

# ── R0. Empty message ─────────────────────────────────────────────────────
# Fail-to-fail: all three fail cases turn into passes if R0 is removed (the
# validator would then find no violation in an empty message).
echo "# R0 empty message"
expect_fail "R0.1 empty file fails" "R0" ""
expect_fail "R0.2 only whitespace lines fails" "R0" $'   \n\n\t'
expect_fail "R0.3 only comment lines fails" "R0" $'# Please enter the commit message\n# Lines starting with # are ignored'
expect_pass "R0.4 a valid subject with comment lines passes" $'feat: add y\n# a comment'

# ── R1. Allowed types ─────────────────────────────────────────────────────
echo "# R1 type"
for t in feat fix build chore ci docs style refactor perf test revert; do
	expect_pass "R1.1 type '$t' passes" "$t: add y"
done
expect_fail "R1.2 unknown type 'feature' fails" "R1" "feature: add y"
expect_fail "R1.3 branch-only type 'hotfix' fails" "R1" "hotfix: add y"
expect_fail "R1.4 missing type fails" "R1" ": add y"
expect_fail "R1.5 free text without a type fails" "R1 R5" "bad message"

# ── R2. Lowercase type and scope ──────────────────────────────────────────
echo "# R2 lowercase"
expect_fail "R2.1 uppercase first letter of the type fails" "R2" "Feat: add y"
expect_fail "R2.2 uppercase scope fails" "R2" "feat(API): add y"
expect_pass "R2.3 lowercase type and scope pass" "feat(api): add y"

# ── R3. Scope grammar ─────────────────────────────────────────────────────
echo "# R3 scope"
expect_pass "R3.1 scope with dot, slash, underscore, hyphen, digit passes" "feat(x.y/z_a-1): add y"
expect_pass "R3.2 single character scope passes" "feat(a): add y"
expect_fail "R3.3 empty scope fails" "R3" "feat(): add y"
expect_fail "R3.4 scope with a space fails" "R3" "feat(my scope): add y"
expect_fail "R3.5 scope with a character outside the set fails" "R3" "feat(a@b): add y"
expect_fail "R3.6 scope that starts with a hyphen fails" "R3" "feat(-x): add y"
expect_fail "R3.7 scope without a closing parenthesis fails" "R3" "feat(api: add y"
expect_pass "R3.8 parentheses in the description are not a scope" "feat: handle (edge) cases"

# ── R4. Breaking-change mark ──────────────────────────────────────────────
echo "# R4 bang"
expect_pass "R4.1 bang before the colon passes" "feat!: add y"
expect_pass "R4.2 bang after the scope passes" "feat(api)!: add y"
expect_fail "R4.3 bang before the scope fails" "R4" "feat!(api): add y"
expect_fail "R4.4 two bangs fail" "R4" "feat(api)!!: add y"

# ── R5. Colon, one space, then text ───────────────────────────────────────
echo "# R5 separator"
expect_pass "R5.1 colon and one space pass" "feat: add y"
expect_fail "R5.2 no space after the colon fails" "R5" "feat:add y"
expect_fail "R5.3 two spaces after the colon fail" "R5" "feat:  add y"
expect_fail "R5.4 no colon fails" "R5" "feat add y"
expect_fail "R5.5 space before the colon fails" "R5" "feat(api) : add y"
expect_fail "R5.6 empty description fails" "R5" "feat:"

# ── R6. First line length ─────────────────────────────────────────────────
echo "# R6 length"
PAD66=$(printf '%66s' '' | tr ' ' a)
expect_pass "R6.1 a first line of exactly 72 characters passes" "feat: $PAD66"
expect_fail "R6.2 a first line of 73 characters fails" "R6" "feat: ${PAD66}a"

# ── R7. No trailing period ────────────────────────────────────────────────
echo "# R7 period"
expect_fail "R7.1 trailing period fails" "R7" "feat: add y."
expect_fail "R7.2 trailing period before trailing spaces fails" "R7" "feat: add y.  "
expect_pass "R7.3 a period inside the line passes" "feat: bump to v1.2"

# ── R8. No WIP ────────────────────────────────────────────────────────────
echo "# R8 WIP"
expect_fail "R8.1 standalone WIP fails" "R8" "feat: add WIP flag"
expect_fail "R8.2 standalone lowercase wip fails" "R8" "fix: wip cleanup"
expect_fail "R8.3 mixed case Wip at the end fails" "R8" "fix: cleanup Wip"
expect_pass "R8.4 wipe is not the word WIP" "fix: wipe the cache"
expect_pass "R8.5 swipe is not the word WIP" "fix: swipe handler"

# ── R9. Blank line before the body ────────────────────────────────────────
echo "# R9 blank line"
expect_fail "R9.1 body on line 2 fails" "R9" $'feat: add y\nbody starts here'
expect_pass "R9.2 blank line then body passes" $'feat: add y\n\nbody starts here'
expect_pass "R9.3 a subject and trailing blank lines pass" $'feat: add y\n\n\n'

# ── R10. Footer token ─────────────────────────────────────────────────────
# Footer lines are checked in the last paragraph only. A label of one to three
# words before ": " must be one hyphenated word, or exactly BREAKING CHANGE.
echo "# R10 footer"
expect_fail "R10.1 a token with a space fails" "R10" $'fix: add y\n\nSome body.\n\nReviewed by: Z'
expect_fail "R10.2 lowercase 'breaking change:' fails" "R10" $'feat!: add y\n\nbreaking change: y is gone'
expect_fail "R10.3 lowercase 'breaking-change:' fails" "R10" $'feat!: add y\n\nbreaking-change: y is gone'
expect_fail "R10.4 a bad footer after a good one fails" "R10" $'fix: add y\n\nRefs: D-1\nSigned off by: Z'
expect_pass "R10.5 hyphenated token passes" $'fix: add y\n\nReviewed-by: Z'
expect_pass "R10.6 hash form passes" $'fix: add y\n\nCloses #12'
expect_pass "R10.7 Refs with a hash passes" $'fix: add y\n\nRefs: #12'
expect_pass "R10.8 Co-authored-by with an email passes" $'fix: add y\n\nCo-authored-by: Ana <ana@example.com>'
expect_pass "R10.9 prose with a long label before the colon passes" $'fix: add y\n\nI changed the parser because it broke: now it works.'
expect_pass "R10.10 a bad token outside the last paragraph passes" $'fix: add y\n\nReviewed by: Z\n\nMore body.'
expect_pass "R10.11 a prose body with no label passes" $'fix: add y\n\nThe parser read the wrong file.'

# ── R11. Breaking footer needs the bang ───────────────────────────────────
echo "# R11 breaking footer"
expect_fail "R11.1 BREAKING CHANGE footer without a bang fails" "R11" $'feat: add y\n\nBREAKING CHANGE: y is gone'
expect_fail "R11.2 BREAKING-CHANGE footer without a bang fails" "R11" $'feat: add y\n\nBREAKING-CHANGE: y is gone'
expect_pass "R11.3 BREAKING CHANGE footer with a bang passes" $'feat!: add y\n\nBREAKING CHANGE: y is gone'
expect_pass "R11.4 BREAKING-CHANGE footer with scope and bang passes" $'feat(api)!: add y\n\nBREAKING-CHANGE: y is gone'
expect_pass "R11.5 a bang without a footer passes" "feat!: add y"

# ── Exempt subjects (D-016) ───────────────────────────────────────────────
echo "# Exemptions"
expect_pass "E.1 a Merge subject passes (and may exceed 72 characters)" "Merge branch 'claude-feat/commit-msg-lint' of github.com:owner/repo into main"
expect_pass "E.2 git's default Revert subject passes" 'Revert "feat: add y"'
expect_pass "E.3 a fixup! subject passes" "fixup! feat: add y"
expect_pass "E.4 a squash! subject passes" "squash! docs: fix typo"
expect_fail "E.5 a lowercase 'merge' subject is not exempt" "R1 R5" "merge branch x"
expect_fail "E.6 Revert without quotes is not exempt" "R2 R5" "Revert feat: add y"
expect_fail "E.7 a comment-only message is empty, not exempt" "R0" $'# Merge branch x'

# ── Message cleanup, as git does it ───────────────────────────────────────
echo "# Cleanup"
expect_pass "C.1 CRLF line endings pass" $'feat: add y\r'
expect_pass "C.2 leading blank lines are ignored" $'\n\nfeat: add y'
expect_pass "C.3 a comment line between body paragraphs is ignored" $'feat: add y\n\nbody\n# comment\nmore body'
expect_pass "C.4 a whitespace-only line counts as blank" $'feat: add y\n   \nbody'

# ── Spec examples (Conventional Commits 1.0.0) ────────────────────────────
echo "# Spec examples"
expect_pass "S.1 plain description" "docs: correct spelling of CHANGELOG"
expect_pass "S.2 scope and capitalized description" "feat(lang): add Polish language"
expect_pass "S.3 bang and BREAKING CHANGE footer" $'feat!: allow provided config object to extend other configs\n\nBREAKING CHANGE: `extends` key in config file is now used for extending other config files'
expect_fail "S.4 the spec example with the footer and no bang fails the house rule R11" "R11" $'feat: allow provided config object to extend other configs\n\nBREAKING CHANGE: `extends` key in config file is now used for extending other config files'
expect_pass "S.5 bang with scope" "feat(api)!: send an email to the customer when a product is shipped"
expect_pass "S.6 chore with bang and footer" $'chore!: drop support for Node 6\n\nBREAKING CHANGE: use JavaScript features not available in Node 6.'
expect_pass "S.7 body with Reviewed-by and Refs footers" $'fix: prevent racing of requests\n\nIntroduce a request id and a reference to latest request. Dismiss\nincoming responses other than from latest request.\n\nRemove timeouts which were used to mitigate the racing issue but are\nobsolete now.\n\nReviewed-by: Z\nRefs: #123'
expect_pass "S.8 revert with a Refs footer" $'revert: let us never again speak of the noodle incident\n\nRefs: 676104e, a215868'
expect_pass "S.9 Refs with the hash form" $'fix: correct minor typos in code\n\nsee the issue for details\n\non typos fixed.\n\nReviewed-by: Z\nRefs #133'

# ── Output format and arguments ───────────────────────────────────────────
echo "# Output and arguments"
run_lint $'Feat(a b):add y.'
BAD_LINES=$(printf '%s\n' "$LINT_ERR" | grep -cv '^commit-msg-lint: R[0-9][0-9]* .')
assert_eq "O.1 every stderr line reads 'commit-msg-lint: R<n> <reason>'" "0" "$BAD_LINES"
assert_eq "O.2 a message with four faults reports each rule once" "R2 R3 R5 R7" "$(rules_hit)"
TYPES_OUT=$("$BASH" "$LINT" --types 2>&1)
assert_eq "O.3 --types prints the allowed types, one per line" "feat fix build chore ci docs style refactor perf test revert" \
	"$(printf '%s\n' "$TYPES_OUT" | tr '\n' ' ' | sed 's/ $//')"
"$BASH" "$LINT" >/dev/null 2>&1
assert_eq "O.4 no argument exits 2" "2" "$?"
"$BASH" "$LINT" "$WORK/no-such-file" >/dev/null 2>&1
assert_eq "O.5 a missing message file exits 2" "2" "$?"

# ── Summary ───────────────────────────────────────────────────────────────
if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$LINT"
fi
echo
echo "test-commit-msg-lint: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
