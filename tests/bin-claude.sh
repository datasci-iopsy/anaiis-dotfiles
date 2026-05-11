#!/usr/bin/env bash
# STALE: bin/claude was deleted 2026-05-11. This test will fail. Kept for historical reference.
# tests/bin-claude.sh, verification harness for bin/claude wrapper.
#
# Runs deterministic scenarios from the audit plan Phase 3 (sections 3.1
# through 3.9). Exits 0 on full pass; non-zero on first failure.
#
# Usage:
#   bash tests/bin-claude.sh                           # full suite
#   docker run --rm -v "$PWD:/r" -w /r bash:5.2 bash tests/bin-claude.sh   # Linux
#
# Each scenario uses a stub `claude` at tests/fixtures/realclaude/claude
# that echoes its argv to stdout, so we can assert exact pass-through
# behavior without invoking a real Claude install.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_DIR/bin/claude"
FIXTURE_DIR="$REPO_DIR/tests/fixtures/realclaude"
FIXTURE="$FIXTURE_DIR/claude"
STAGING="${HOME}/.claude/coderabbit-staged-batch.md"

# Use a sandbox HOME so we don't touch the real ~/.claude during tests.
SANDBOX_HOME="$(mktemp -d)"
trap 'rm -rf "$SANDBOX_HOME"' EXIT

PASS=0
FAIL=0

assert() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' \
			"$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

assert_contains() {
	local name="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected to contain: %s\n        actual:   %s\n' \
			"$name" "$needle" "$haystack"
		FAIL=$((FAIL + 1))
	fi
}

# ── Setup: create the stub real claude ────────────────────────────────────
mkdir -p "$FIXTURE_DIR"
cat >"$FIXTURE" <<'STUB'
#!/usr/bin/env bash
# Stub real claude, echoes argv, exits 0.
echo "STUB_CLAUDE argv=[$*]"
STUB
chmod +x "$FIXTURE"

# ── 3.1: shebang and executable ───────────────────────────────────────────
echo "# 3.1 shebang + executable"
assert "3.1a wrapper is executable" "0" "$(
	[ -x "$WRAPPER" ]
	echo $?
)"
assert "3.1b shebang correct" "#!/usr/bin/env bash" "$(head -1 "$WRAPPER")"

# ── 3.2: bash resolves to wrapper when in PATH first ──────────────────────
echo "# 3.2 bash resolves wrapper"
RESOLVED=$(PATH="$REPO_DIR/bin:$FIXTURE_DIR:$PATH" bash -c 'command -v claude')
assert "3.2 bash resolves to wrapper" "$WRAPPER" "$RESOLVED"

# ── 3.3: zsh resolution (skip if zsh missing) ─────────────────────────────
if command -v zsh >/dev/null 2>&1; then
	echo "# 3.3 zsh resolves wrapper"
	RESOLVED_Z=$(PATH="$REPO_DIR/bin:$FIXTURE_DIR:$PATH" zsh -c 'command -v claude')
	assert "3.3 zsh resolves to wrapper" "$WRAPPER" "$RESOLVED_Z"
else
	echo "# 3.3 zsh not installed, skipped"
fi

# ── 3.4: pass-through (no batch) ──────────────────────────────────────────
echo "# 3.4 pass-through with no batch"
HOME="$SANDBOX_HOME" PATH="$REPO_DIR/bin:$FIXTURE_DIR:$PATH" \
	bash -c 'claude foo bar' >/tmp/bin-claude.out 2>&1
OUT=$(cat /tmp/bin-claude.out)
assert_contains "3.4a stub invoked with pass-through args" "STUB_CLAUDE argv=[foo bar]" "$OUT"
assert "3.4b no staging file written" "1" "$(
	[ -f "$SANDBOX_HOME/.claude/coderabbit-staged-batch.md" ]
	echo $?
)"

# ── 3.5: batch detection ──────────────────────────────────────────────────
echo "# 3.5 batch detection"
BATCH_INPUT="Some preamble.
Verify each finding against the current code at line 1.
Verify each finding against the current code at line 2.
Some trailing notes."
HOME="$SANDBOX_HOME" PATH="$REPO_DIR/bin:$FIXTURE_DIR:$PATH" \
	bash -c 'claude "$1"' _ "$BATCH_INPUT" >/tmp/bin-claude.out 2>&1
OUT=$(cat /tmp/bin-claude.out)
assert "3.5a staging file created" "0" "$(
	[ -f "$SANDBOX_HOME/.claude/coderabbit-staged-batch.md" ]
	echo $?
)"
if [ -f "$SANDBOX_HOME/.claude/coderabbit-staged-batch.md" ]; then
	STAGED=$(cat "$SANDBOX_HOME/.claude/coderabbit-staged-batch.md")
	assert_contains "3.5b staging file has Findings: 2" "Findings: 2" "$STAGED"
fi
assert_contains "3.5c stub invoked with NO args after shift" "STUB_CLAUDE argv=[]" "$OUT"
assert_contains "3.5d notice line printed" "[CodeRabbit] 2 finding(s) staged" "$OUT"

# ── 3.6: resolver collision (a non-executable claude earlier in PATH) ─────
echo "# 3.6 resolver collision"
COLL_DIR=$(mktemp -d)
touch "$COLL_DIR/claude" # exists but not executable
HOME="$SANDBOX_HOME" PATH="$REPO_DIR/bin:$COLL_DIR:$FIXTURE_DIR:$PATH" \
	bash -c 'claude check' >/tmp/bin-claude.out 2>&1
OUT=$(cat /tmp/bin-claude.out)
rm -rf "$COLL_DIR"
assert_contains "3.6 wrapper falls through to next executable claude" "STUB_CLAUDE argv=[check]" "$OUT"

# ── 3.8: bash/ layer, shared.bash is the only tracked file ──────────────
echo "# 3.8 bash/ tracks only shared.bash"
TRACKED_BASH=$(cd "$REPO_DIR" && git ls-files bash/ 2>/dev/null)
assert "3.8 git ls-files bash/ returns only shared.bash" "bash/shared.bash" "$TRACKED_BASH"

# ── 3.9: install.sh prints PATH-extension snippet, no bash symlinks ───────
echo "# 3.9 install.sh output shape"
INSTALL_OUT=$(grep -E 'dotfiles/bin' "$REPO_DIR/install.sh" || true)
assert_contains "3.9 install.sh references dotfiles/bin in PATH-extension snippet" '.dotfiles/bin' "$INSTALL_OUT"

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "Phase 3 wrapper tests: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
