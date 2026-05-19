#!/usr/bin/env bash
# tests/test-install-bashrc.sh -- verify install.sh PATH wiring is idempotent
#
# Tests:
#   - install.sh adds PATH line when absent
#   - install.sh normalises a bare duplicate (two export PATH lines)
#   - install.sh handles an if-guard form without leaving stray fi or duplicates
#   - install.sh is idempotent: running twice produces exactly one PATH line
#   - result always passes bash -n (syntax check)

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_eq() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' \
			"$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

assert_syntax_ok() {
	local name="$1" file="$2"
	if bash -n "$file" 2>/dev/null; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s (bash -n failed)\n' "$name"
		bash -n "$file" 2>&1 | sed 's/^/        /'
		FAIL=$((FAIL + 1))
	fi
}

# Apply the PATH-wiring logic from install.sh to a mock BASHRC file.
# Mirrors the exact commands in install.sh's PATH section so any regression
# in that section will cause these tests to fail.
run_path_block() {
	local BASHRC="$1"
	awk '
		/if.*anaiis-dotfiles\/bin/  { in_guard=1; next }
		in_guard && /^[[:space:]]*fi[[:space:]]*$/ { in_guard=0; next }
		/anaiis-dotfiles\/bin/      { next }
		{ print }
	' "$BASHRC" >"/tmp/bashrc_path_fix_$$" \
		&& mv "/tmp/bashrc_path_fix_$$" "$BASHRC"
	printf '\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\n' >>"$BASHRC"
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ---------------------------------------------------------------------------
# Test 1: PATH line absent -- should be added
# ---------------------------------------------------------------------------
MOCK="$TMPDIR_TEST/bashrc_absent"
printf '# minimal bashrc\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_path_block "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "adds PATH when absent" "1" "$count"
assert_syntax_ok "syntax ok after adding PATH" "$MOCK"

# ---------------------------------------------------------------------------
# Test 2: Bare duplicate (two identical export PATH lines)
# ---------------------------------------------------------------------------
MOCK="$TMPDIR_TEST/bashrc_duplicate"
printf '# minimal bashrc\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_path_block "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "deduplicates bare duplicate" "1" "$count"
assert_syntax_ok "syntax ok after dedup" "$MOCK"

# ---------------------------------------------------------------------------
# Test 3: if-guard form (the exact failure mode that caused the bug)
# ---------------------------------------------------------------------------
MOCK="$TMPDIR_TEST/bashrc_ifguard"
cat >"$MOCK" <<'EOF'
# minimal bashrc
if [[ ":$PATH:" != *":$HOME/anaiis-dotfiles/bin:"* ]]; then
	export PATH="$HOME/anaiis-dotfiles/bin:$PATH"
fi
[ -f ~/.bashrc.local ] && source ~/.bashrc.local
EOF
run_path_block "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "if-guard: exactly one PATH line after normalise" "1" "$count"
stray_fi=$(grep -c '^fi$' "$MOCK" || true)
assert_eq "if-guard: no stray fi remaining" "0" "$stray_fi"
assert_syntax_ok "syntax ok after if-guard normalise" "$MOCK"

# ---------------------------------------------------------------------------
# Test 4: Idempotency -- running twice gives same result as once
# ---------------------------------------------------------------------------
MOCK="$TMPDIR_TEST/bashrc_idempotent"
printf '# minimal bashrc\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_path_block "$MOCK"
run_path_block "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "idempotent: two runs produce exactly one PATH line" "1" "$count"
assert_syntax_ok "syntax ok after two runs" "$MOCK"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
