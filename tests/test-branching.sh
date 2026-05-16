#!/usr/bin/env bash
# tests/test-branching.sh -- verify branching rules and hooks
#
# Tests:
#   - block-edit-on-main.sh still fires on main (regression)
#   - block-edit-on-main.sh message suggests worktree creation
#   - block-edit-on-main.sh still exempts ~/.claude/plans/ paths
#   - list-merged-claude-branches.sh outputs advisory when merged branches exist
#   - list-merged-claude-branches.sh is silent when no merged claude/* branches exist
#   - rules/branching.md exists with required section headings
#   - settings.json registers list-merged-claude-branches.sh
#
# Note: Scenarios 01-05 from the plan (trivial vs. non-trivial edit,
# branch reuse, worktree creation from main) require Claude runtime
# behavior and are verified manually via Phase 6 smoke tests.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCK_HOOK="$REPO_DIR/claude/hooks/block-edit-on-main.sh"
ADVISORY_HOOK="$REPO_DIR/claude/hooks/list-merged-claude-branches.sh"
BRANCHING_RULE="$REPO_DIR/claude/rules/branching.md"
SETTINGS="$REPO_DIR/claude/settings.json"

PASS=0
FAIL=0

assert_exit() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected exit=%s, got %s\n' \
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
		printf '  FAIL  %s\n        expected to contain: %s\n' \
			"$name" "$needle"
		FAIL=$((FAIL + 1))
	fi
}

assert_not_contains() {
	local name="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		printf '  FAIL  %s\n        expected NOT to contain: %s\n' \
			"$name" "$needle"
		FAIL=$((FAIL + 1))
	else
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	fi
}

# Helper: run block-edit-on-main.sh inside a temp repo on a given branch.
# Usage: run_block_hook <branch> <file_path>
run_block_hook() {
	local branch="$1" file="$2"
	local tmpdir
	tmpdir=$(mktemp -d)
	(
		cd "$tmpdir" || exit 1
		git init -q
		git commit -q --allow-empty -m "init"
		if [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
			git checkout -q -b "$branch" 2>/dev/null
		fi
		printf '{"tool_input":{"file_path":"%s"}}' "$file" \
			| bash "$BLOCK_HOOK" 2>/tmp/block-hook.stderr
		echo $?
	)
	rm -rf "$tmpdir"
}

# Helper: run list-merged-claude-branches.sh inside a temp repo with
# optional merged claude/* branches pre-created.
# merged_branches: space-separated branch names that should be marked merged.
run_advisory_hook() {
	local merged_branches="${1:-}"
	local tmpdir
	tmpdir=$(mktemp -d)
	local output
	output=$(
		cd "$tmpdir" || exit 1
		git init -q
		git commit -q --allow-empty -m "init"
		if [ -n "$merged_branches" ]; then
			for br in $merged_branches; do
				git checkout -q -b "$br" 2>/dev/null
				git commit -q --allow-empty -m "work on $br"
				git checkout -q main 2>/dev/null
				git merge -q --no-ff "$br" -m "merge $br" 2>/dev/null
			done
		fi
		# Remove the date-gated flag so the hook runs fresh.
		rm -f "/tmp/claude-branch-hygiene-$(date +%Y%m%d)"
		bash "$ADVISORY_HOOK" 2>&1
	)
	rm -rf "$tmpdir"
	printf '%s' "$output"
}

# ── 1. Hook files exist and are executable ────────────────────────────────
echo "# 1. Hook files"
[ -f "$BLOCK_HOOK" ] \
	&& {
		PASS=$((PASS + 1))
		echo "  PASS  1.1 block-edit-on-main.sh exists"
	} \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  1.1 block-edit-on-main.sh missing"
	}
[ -x "$BLOCK_HOOK" ] \
	&& {
		PASS=$((PASS + 1))
		echo "  PASS  1.2 block-edit-on-main.sh executable"
	} \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  1.2 block-edit-on-main.sh not executable"
	}
[ -f "$ADVISORY_HOOK" ] \
	&& {
		PASS=$((PASS + 1))
		echo "  PASS  1.3 list-merged-claude-branches.sh exists"
	} \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  1.3 list-merged-claude-branches.sh missing"
	}
[ -x "$ADVISORY_HOOK" ] \
	&& {
		PASS=$((PASS + 1))
		echo "  PASS  1.4 list-merged-claude-branches.sh executable"
	} \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  1.4 list-merged-claude-branches.sh not executable"
	}

# ── 2. block-edit-on-main regression ─────────────────────────────────────
echo "# 2. block-edit-on-main regression"
RC=$(run_block_hook "main" "/tmp/somefile.sh")
assert_exit "2.1 blocks edit on main (exit 2)" "2" "$RC"

RC=$(run_block_hook "feat/my-feature" "/tmp/somefile.sh")
assert_exit "2.2 allows edit on feature branch (exit 0)" "0" "$RC"

RC=$(run_block_hook "claude/some-topic" "/tmp/somefile.sh")
assert_exit "2.3 allows edit on claude/* branch (exit 0)" "0" "$RC"

# ── 3. block-edit-on-main message content ────────────────────────────────
echo "# 3. block message suggests worktree"
run_block_hook "main" "/tmp/somefile.sh" >/dev/null 2>/tmp/block-hook.stderr || true
STDERR=$(cat /tmp/block-hook.stderr)
assert_contains "3.1 message mentions worktree" "worktree" "$STDERR"
assert_contains "3.2 message mentions claude/<topic>" "claude/<topic>" "$STDERR"
assert_contains "3.3 message mentions git worktree add" "git worktree add" "$STDERR"

# ── 4. block-edit-on-main plans exemption ────────────────────────────────
echo "# 4. plans/ exemption"
PLANS_DIR="$HOME/.claude/plans"
mkdir -p "$PLANS_DIR"
RC=$(run_block_hook "main" "$PLANS_DIR/my-plan.md")
assert_exit "4.1 plans path exempt from block on main (exit 0)" "0" "$RC"

# ── 5. advisory hook with merged claude/* branches ────────────────────────
echo "# 5. advisory hook with merged branches"
if command -v git >/dev/null 2>&1; then
	OUTPUT=$(run_advisory_hook "claude/old-topic claude/another-topic")
	assert_contains "5.1 advisory mentions branch-hygiene" "[branch-hygiene]" "$OUTPUT"
	assert_contains "5.2 advisory lists a merged branch" "claude/" "$OUTPUT"
	assert_contains "5.3 advisory shows delete command" "git branch -d" "$OUTPUT"
else
	echo "  SKIP  git not found"
fi

# ── 6. advisory hook with no merged claude/* branches ─────────────────────
echo "# 6. advisory hook when nothing to clean"
OUTPUT=$(run_advisory_hook "")
assert_not_contains "6.1 no output when no merged claude/* branches" \
	"[branch-hygiene]" "$OUTPUT"

# ── 7. rules/branching.md structure ──────────────────────────────────────
echo "# 7. branching rule file content"
[ -f "$BRANCHING_RULE" ] \
	&& {
		PASS=$((PASS + 1))
		echo "  PASS  7.1 rules/branching.md exists"
	} \
	|| {
		FAIL=$((FAIL + 1))
		echo "  FAIL  7.1 rules/branching.md missing"
	}

if [ -f "$BRANCHING_RULE" ]; then
	for section in "Trivial" "Branch reuse" "Worktree" "Cleanup"; do
		if grep -qi "$section" "$BRANCHING_RULE"; then
			printf '  PASS  7.x rule contains section: %s\n' "$section"
			PASS=$((PASS + 1))
		else
			printf '  FAIL  7.x rule missing section: %s\n' "$section"
			FAIL=$((FAIL + 1))
		fi
	done
fi

# ── 8. settings.json registers advisory hook ──────────────────────────────
echo "# 8. settings.json registration"
if command -v jq >/dev/null 2>&1; then
	REG=$(jq -r '
		[.hooks.UserPromptSubmit[]
			| .hooks[]
			| select(.command | contains("list-merged-claude-branches.sh"))
			| .command
		] | length' "$SETTINGS")
	if [ "$REG" -gt 0 ]; then
		PASS=$((PASS + 1))
		echo "  PASS  8.1 advisory hook registered in UserPromptSubmit"
	else
		FAIL=$((FAIL + 1))
		echo "  FAIL  8.1 advisory hook not found in settings.json UserPromptSubmit"
	fi
else
	echo "  SKIP  jq not found"
fi

rm -f /tmp/block-hook.stderr

echo
echo "──────────────────────────────────────────────"
echo "test-branching: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
