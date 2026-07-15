#!/bin/bash
# test-compact-hooks.sh, verify pre-compact.sh behavior
#
# Usage: bash tests/test-compact-hooks.sh
#
# post-compact.sh was retired (its systemMessage restore never reached the
# model). The compact-source restore path now lives in session-start-context.sh
# and is covered by tests/test-session-start-context.sh.
#
# Tests: automated assertions on hook outputs and file creation.
# Manual scenarios are documented at the bottom and require a live session.

set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
PASS=0
FAIL=0

# ── Test helpers ──────────────────────────────────────────────────────────────

pass() {
	echo "  PASS  $1"
	PASS=$((PASS + 1))
}
fail() {
	echo "  FAIL  $1"
	FAIL=$((FAIL + 1))
}

assert_file_exists() {
	local label="$1" path="$2"
	[ -f "$path" ] && pass "$label" || fail "$label, missing: $path"
}

assert_file_missing() {
	local label="$1" path="$2"
	[ ! -f "$path" ] && pass "$label" || fail "$label, should not exist: $path"
}

assert_contains() {
	local label="$1" file="$2" pattern="$3"
	grep -q "$pattern" "$file" 2>/dev/null && pass "$label" || fail "$label, pattern not found: '$pattern'"
}

assert_not_contains() {
	local label="$1" file="$2" pattern="$3"
	! grep -q "$pattern" "$file" 2>/dev/null && pass "$label" || fail "$label, unexpected pattern found: '$pattern'"
}

# ── Test environment setup ────────────────────────────────────────────────────

setup_test_env() {
	TEST_HOME=$(mktemp -d)
	TEST_CWD=$(mktemp -d)
	TEST_DATE=$(date +"%Y-%m-%d")

	# Initialize a git repo in TEST_CWD
	git -C "$TEST_CWD" init -q
	git -C "$TEST_CWD" config user.email "test@test.com"
	git -C "$TEST_CWD" config user.name "Test"
	echo "test" >"$TEST_CWD/test.txt"
	git -C "$TEST_CWD" add test.txt
	git -C "$TEST_CWD" commit -q -m "init"

	# Derive project key (same formula as hook scripts)
	TEST_PROJECT_KEY=$(echo "$TEST_CWD" | tr '/.' '-')
	TEST_MEMORY_DIR="$TEST_HOME/.claude/projects/$TEST_PROJECT_KEY/memory"
	mkdir -p "$TEST_MEMORY_DIR"

	# Create a mock session transcript
	TEST_SESSION_ID="testsession12345678"
	TEST_TRANSCRIPT="$TEST_HOME/.claude/projects/$TEST_PROJECT_KEY/${TEST_SESSION_ID}.jsonl"

	cat >"$TEST_TRANSCRIPT" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/Users/test/anaiis-dotfiles/claude/settings.json"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/Users/test/anaiis-dotfiles/claude/rules/session.md","old_string":"foo","new_string":"bar"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Read","input":{"file_path":"/Users/test/anaiis-dotfiles/claude/settings.json"}}]}}
EOF
}

teardown_test_env() {
	rm -rf "$TEST_HOME" "$TEST_CWD"
}

run_pre_compact() {
	local trigger="${1:-manual}"
	local session="${2:-$TEST_SESSION_ID}"
	local cwd="${3:-$TEST_CWD}"
	local input
	input=$(jq -n \
		--arg trigger "$trigger" \
		--arg session_id "$session" \
		--arg cwd "$cwd" \
		'{"trigger": $trigger, "session_id": $session_id, "cwd": $cwd, "hook_event_name": "PreCompact"}')
	# HOME must be set for bash, not for echo, pipe passes stdin, not env
	# `|| true`: a hook failure must be an assertable test outcome, not a
	# crash of this harness (which runs under set -e).
	echo "$input" | HOME="$TEST_HOME" bash "$HOOK_DIR/pre-compact.sh" 2>/dev/null || true
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_pre_compact_creates_handoff() {
	echo
	echo "── test_pre_compact_creates_handoff"
	setup_test_env
	run_pre_compact "manual"
	# Hook writes to memory/handoffs/ with ISO timestamp filename
	local expected_file
	expected_file=$(ls "$TEST_MEMORY_DIR/handoffs"/handoff_*.md 2>/dev/null | head -1 || echo "")
	assert_file_exists "handoff file created" "$expected_file"
	assert_contains "trigger field present" "$expected_file" "Trigger.*manual"
	assert_contains "branch field present" "$expected_file" "Branch:"
	assert_contains "session id present" "$expected_file" "Session:"
	assert_contains "project cwd present" "$expected_file" "Project:"
	teardown_test_env
}

test_pre_compact_extracts_file_reads() {
	echo
	echo "── test_pre_compact_extracts_file_reads"
	setup_test_env
	run_pre_compact "manual"
	# Hook writes to memory/handoffs/ with ISO timestamp filename
	local handoff_file
	handoff_file=$(ls "$TEST_MEMORY_DIR/handoffs"/handoff_*.md 2>/dev/null | head -1 || echo "")
	assert_contains "Read tool path captured" "$handoff_file" "Read: /Users/test/anaiis-dotfiles/claude/settings.json"
	assert_contains "Edit tool path captured" "$handoff_file" "Edit: /Users/test/anaiis-dotfiles/claude/rules/session.md"
	teardown_test_env
}

test_pre_compact_no_memory_md_side_effect() {
	echo
	echo "── test_pre_compact_no_memory_md_side_effect"
	# Hook writes to handoffs/ only; MEMORY.md is never mutated.
	# Multiple runs within the same minute share a filename (minute-precision ISO
	# timestamp), so we only assert >= 1 file, not an exact count.
	setup_test_env
	run_pre_compact "manual"
	run_pre_compact "auto"
	local count
	count=$(find "$TEST_MEMORY_DIR/handoffs" -maxdepth 1 -name 'handoff_*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
	[ "${count:-0}" -ge 1 ] && pass "at least one handoff file written" || fail "no handoff files found"
	assert_file_missing "MEMORY.md not touched by hook" "$TEST_MEMORY_DIR/MEMORY.md"
	teardown_test_env
}

test_pre_compact_no_git_repo() {
	echo
	echo "── test_pre_compact_no_git_repo"
	setup_test_env
	local no_git_dir
	no_git_dir=$(mktemp -d)
	run_pre_compact "manual" "$TEST_SESSION_ID" "$no_git_dir"
	local proj_key
	proj_key=$(echo "$no_git_dir" | tr '/.' '-')
	local handoff_file
	handoff_file=$(ls "$TEST_HOME/.claude/projects/$proj_key/memory/handoffs"/handoff_*.md 2>/dev/null | head -1 || echo "")
	assert_file_exists "handoff created even without git" "$handoff_file"
	assert_contains "no-git marker present" "$handoff_file" "not a git repo"
	rm -rf "$no_git_dir"
	teardown_test_env
}

test_pre_compact_no_transcript() {
	echo
	echo "── test_pre_compact_no_transcript"
	setup_test_env
	# Use a brand-new CWD with no project dir (and thus no JSONL files anywhere)
	local empty_cwd
	empty_cwd=$(mktemp -d)
	git -C "$empty_cwd" init -q
	git -C "$empty_cwd" config user.email "test@test.com"
	git -C "$empty_cwd" config user.name "Test"
	local proj_key
	proj_key=$(echo "$empty_cwd" | tr '/.' '-')
	local mem_dir="$TEST_HOME/.claude/projects/$proj_key/memory"
	run_pre_compact "auto" "nosuchsession" "$empty_cwd"
	local handoff_file
	handoff_file=$(ls "$mem_dir/handoffs"/handoff_*.md 2>/dev/null | head -1 || echo "")
	assert_file_exists "handoff created without transcript" "$handoff_file"
	assert_contains "graceful fallback message" "$handoff_file" "no file reads detected"
	rm -rf "$empty_cwd"
	teardown_test_env
}

test_pre_compact_auto_trigger() {
	echo
	echo "── test_pre_compact_auto_trigger"
	setup_test_env
	run_pre_compact "auto"
	local handoff_file
	handoff_file=$(ls "$TEST_MEMORY_DIR/handoffs"/handoff_*.md 2>/dev/null | head -1 || echo "")
	assert_contains "auto trigger recorded" "$handoff_file" "Trigger.*auto"
	# MEMORY.md is not touched; verify the file was written to handoffs/
	assert_file_missing "MEMORY.md not touched for auto trigger" "$TEST_MEMORY_DIR/MEMORY.md"
	teardown_test_env
}

test_pre_compact_memory_capped_at_five() {
	echo
	echo "── test_pre_compact_memory_capped_at_five"
	setup_test_env
	# Seed handoffs/ with 5 existing files (hook caps at 5 in handoffs/)
	local mem_dir="$TEST_HOME/.claude/projects/$(echo "$TEST_CWD" | tr '/.' '-')/memory"
	local handoffs_dir="$mem_dir/handoffs"
	mkdir -p "$handoffs_dir"
	for i in 1 2 3 4 5; do
		echo "stub" >"$handoffs_dir/handoff_2026-04-2${i}T00-00Z_aabbccdd.md"
	done
	run_pre_compact "manual"
	local count
	count=$(find "$handoffs_dir" -maxdepth 1 -name 'handoff_*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
	[ "$count" -le 5 ] && pass "handoff entries capped at 5" || fail "expected <= 5, got $count"
	teardown_test_env
}

test_pre_compact_sanitizes_unsafe_session_id() {
	echo
	echo "── test_pre_compact_sanitizes_unsafe_session_id"
	setup_test_env
	# A session_id containing path-traversal/separator characters must not be
	# used raw in a filesystem path; it should be treated as absent instead.
	run_pre_compact "manual" "../../tmp/traversal-marker"
	local handoff_file
	handoff_file=$(find "$TEST_MEMORY_DIR/handoffs" -maxdepth 1 -name 'handoff_*.md' -type f 2>/dev/null | head -1)
	assert_file_exists "handoff still written with unsafe session_id" "$handoff_file"
	if [ -n "$handoff_file" ]; then
		case "$(basename "$handoff_file")" in
			*traversal* | *..*)
				fail "unsafe session_id characters leaked into handoff filename: $(basename "$handoff_file")"
				;;
			*)
				pass "unsafe session_id characters excluded from handoff filename"
				;;
		esac
	fi
	teardown_test_env
}

test_pre_compact_empty_cwd() {
	echo
	echo "── test_pre_compact_empty_cwd"
	local input='{"trigger":"manual","session_id":"abc123","cwd":"","hook_event_name":"PreCompact"}'
	local exit_code=0
	echo "$input" | bash "$HOOK_DIR/pre-compact.sh" 2>/dev/null || exit_code=$?
	[ "$exit_code" -eq 0 ] && pass "exits 0 with empty cwd" || fail "non-zero exit with empty cwd"
}

# ── Run all automated tests ───────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════"
echo " Compact hook tests"
echo "═══════════════════════════════════════════════════════"

test_pre_compact_creates_handoff
test_pre_compact_extracts_file_reads
test_pre_compact_no_memory_md_side_effect
test_pre_compact_no_git_repo
test_pre_compact_no_transcript
test_pre_compact_auto_trigger
test_pre_compact_memory_capped_at_five
test_pre_compact_sanitizes_unsafe_session_id
test_pre_compact_empty_cwd

echo
echo "═══════════════════════════════════════════════════════"
printf " Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════════════════"

# ── Manual verification scenarios ────────────────────────────────────────────
cat <<'MANUAL'

── MANUAL SCENARIOS (run in a live Claude session) ──────────────────────────

SCENARIO 1: Pre-compact hook fires on /compact
  Step:   Run /compact in any Claude session in a git repo.
  Check:  ls -lt ~/.claude/projects/<project>/memory/handoff_*.md | head -3
  Expect: A new handoff_<today>_*.md file, timestamp within the last minute.
  Expect: ~/.claude/projects/<project>/memory/MEMORY.md updated with pointer.

SCENARIO 2: SessionStart(compact) restores the handoff
  Step:   After /compact, ask: "What files did we read before compaction?"
  Expect: Claude lists files from the restored handoff without calling Read.
          session-start-context.sh (source=compact) delivers this via
          hookSpecificOutput.additionalContext, not the retired post-compact.sh.
  Fail:   Claude says it doesn't know, or calls Read on a file from the list.

SCENARIO 3: File re-read prevention (session.md rule)
  Step:   In a session where settings.json has been read, ask:
          "What is the current autoCompactEnabled value in settings.json?"
  Expect: Claude answers from context. No Read tool call fires.
  Fail:   Claude calls Read(file_path: "...settings.json") again.

SCENARIO 4: Large file offset/limit (session.md rule)
  Step:   Ask Claude to check a specific rule in a file you know is > 200 lines.
  Expect: Claude uses Read with offset/limit, not Read of the full file.
  Fail:   Claude reads the entire file.

SCENARIO 5: Auto-compact hook fires
  Step:   Let a session run until auto-compact triggers (context ~full).
  Check:  ls -lt ~/.claude/projects/<project>/memory/handoff_*.md | head -1
  Expect: Handoff file with trigger=auto, written before the compaction summary.

MANUAL

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
