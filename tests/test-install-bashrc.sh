#!/usr/bin/env bash
# tests/test-install-bashrc.sh -- verify install.sh's ~/.bashrc wiring and
# its CI mode, by running the real installer against a throwaway HOME.
#
# Tests:
#   - install.sh --bashrc-only adds the PATH line when absent
#   - install.sh --bashrc-only normalises a bare duplicate (two export PATH lines)
#   - install.sh --bashrc-only handles an if-guard form without leaving a
#     stray fi or duplicates (the exact failure mode that caused the bug)
#   - install.sh --bashrc-only is idempotent: two runs leave exactly one PATH line
#   - the resulting .bashrc always passes bash -n (syntax check)
#   - install.sh --symlinks-only creates the ~/.claude links and stops before
#     the shell-config phase (used by CI)
#
# Earlier versions of this file re-implemented the installer's awk block
# inside the test and asserted on that copy, so a regression in install.sh
# could not fail them (tasks/trim-candidates.md, 2026-09-07). The
# --bashrc-only mode exists so the installer itself is what runs here.

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

# Run the installer's shell-config phase with HOME pointed at the directory
# that holds the mock .bashrc. The installer reads and rewrites $HOME/.bashrc.
run_bashrc_phase() {
	local mock="$1"
	HOME="$(dirname "$mock")" bash "$INSTALL" --bashrc-only >/dev/null 2>&1
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ---------------------------------------------------------------------------
# Test 1: PATH line absent -- should be added
# Fails if install.sh stops appending the canonical export line.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/absent"
MOCK="$TMPDIR_TEST/absent/.bashrc"
printf '# minimal bashrc\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "adds PATH when absent" "1" "$count"
assert_syntax_ok "syntax ok after adding PATH" "$MOCK"

# ---------------------------------------------------------------------------
# Test 2: Bare duplicate (two identical export PATH lines)
# Fails if install.sh's awk block stops stripping prior PATH lines before
# appending.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/duplicate"
MOCK="$TMPDIR_TEST/duplicate/.bashrc"
printf '# minimal bashrc\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\nexport PATH="$HOME/anaiis-dotfiles/bin:$PATH"\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "deduplicates bare duplicate" "1" "$count"
assert_syntax_ok "syntax ok after dedup" "$MOCK"

# ---------------------------------------------------------------------------
# Test 3: if-guard form (the exact failure mode that caused the bug)
# Fails if install.sh's awk block drops the in_guard handling: the guarded
# export would survive (two PATH lines) or the closing fi would be orphaned.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/ifguard"
MOCK="$TMPDIR_TEST/ifguard/.bashrc"
cat >"$MOCK" <<'EOF'
# minimal bashrc
if [[ ":$PATH:" != *":$HOME/anaiis-dotfiles/bin:"* ]]; then
	export PATH="$HOME/anaiis-dotfiles/bin:$PATH"
fi
[ -f ~/.bashrc.local ] && source ~/.bashrc.local
EOF
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "if-guard: exactly one PATH line after normalise" "1" "$count"
stray_fi=$(grep -c '^fi$' "$MOCK" || true)
assert_eq "if-guard: no stray fi remaining" "0" "$stray_fi"
assert_syntax_ok "syntax ok after if-guard normalise" "$MOCK"

# ---------------------------------------------------------------------------
# Test 4: Idempotency -- running twice gives same result as once
# Fails if install.sh appends without first stripping the line it added on
# the previous run.
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/idempotent"
MOCK="$TMPDIR_TEST/idempotent/.bashrc"
printf '# minimal bashrc\n[ -f ~/.bashrc.local ] && source ~/.bashrc.local\n' >"$MOCK"
run_bashrc_phase "$MOCK"
run_bashrc_phase "$MOCK"
count=$(grep -c 'anaiis-dotfiles/bin' "$MOCK" || true)
assert_eq "idempotent: two runs produce exactly one PATH line" "1" "$count"
assert_syntax_ok "syntax ok after two runs" "$MOCK"

# ---------------------------------------------------------------------------
# Test 5: --symlinks-only links ~/.claude and stops before shell config
#
# Fail-to-fail: the .bashrc assertion fails if the flag is ignored or if the
# early exit is placed after the ~/.bashrc block (a PATH line would appear);
# the memory-link assertion fails if the exit is placed before the Directories
# section; the .lintr assertion fails if the exit is placed after R Style.
# ---------------------------------------------------------------------------
FAKE_HOME="$TMPDIR_TEST/home_symlinks_only"
mkdir -p "$FAKE_HOME"
printf '# untouched\n' >"$FAKE_HOME/.bashrc"
HOME="$FAKE_HOME" bash "$INSTALL" --symlinks-only >/dev/null 2>&1
rc=$?
assert_eq "--symlinks-only: exits 0" "0" "$rc"
assert_eq "--symlinks-only: .bashrc untouched" "# untouched" "$(cat "$FAKE_HOME/.bashrc")"
linked=$(cd "$FAKE_HOME/.claude/memory" 2>/dev/null && pwd -P)
assert_eq "--symlinks-only: ~/.claude/memory resolves into the repo" \
	"$(cd "$REPO_DIR/claude/memory" && pwd -P)" "$linked"
lintr_present=$([ -e "$FAKE_HOME/.lintr" ] && echo 1 || echo 0)
assert_eq "--symlinks-only: .lintr not linked" "0" "$lintr_present"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
