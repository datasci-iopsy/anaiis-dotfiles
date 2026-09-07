#!/usr/bin/env bash
# tests/test-r-lint-staged.sh -- verify r-lint-staged.sh
#
# Confirms: SKIP_R_LINT=1 exits 0 and emits no [r-lint] output. Behavioral
# tests for lint pass/fail require a live R+lintr install and are skipped if
# absent.
#
# Exit 0 if all tests pass; non-zero on any failure.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_DIR/claude/scripts/r-lint-staged.sh"

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

# ── 2. SKIP_R_LINT bypass ─────────────────────────────────────────────────────

echo
echo "--- 2. SKIP_R_LINT=1 bypasses"

TMP_REPO=$(mktemp -d)
(
	cd "$TMP_REPO" \
		&& git init >/dev/null 2>&1 \
		&& git config user.email "t@t.com" >/dev/null 2>&1 \
		&& git config user.name "T" >/dev/null 2>&1 \
		&& printf 'x <- 1\n' >test.R \
		&& git add test.R >/dev/null 2>&1
) >/dev/null 2>&1

OUT=$(cd "$TMP_REPO" && PATH="/usr/bin:/bin" SKIP_R_LINT=1 bash "$SCRIPT" 2>&1)
RC=$?
if [ "$RC" = "0" ]; then
	pass "2.1 SKIP_R_LINT=1 exits 0"
else
	fail "2.1 SKIP_R_LINT=1 should exit 0 (got $RC)"
fi
# Exit 0 alone cannot prove the bypass ran: with a staged R file, every
# non-bypass path also exits 0 on a lint-clean fixture (Rscript missing,
# lintr missing, or no findings) and each of those prints an [r-lint] line.
# Fails if the SKIP_R_LINT early exit is removed from r-lint-staged.sh.
if ! printf '%s' "$OUT" | grep -qF '[r-lint]'; then
	pass "2.1b SKIP_R_LINT=1 emits no [r-lint] output"
else
	fail "2.1b SKIP_R_LINT=1 should emit no [r-lint] output (got: ${OUT:0:120})"
fi
rm -rf "$TMP_REPO"

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo "============================================================"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
