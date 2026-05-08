#!/usr/bin/env bash
# coderabbit-triage.sh -- inject triage rubric when a CodeRabbit review prompt is detected
#
# Triggered by UserPromptSubmit hook. Two modes:
#
# 1. "Fix all" batch (starts with "Fix the following issues"):
#    Stages findings to ~/.claude/coderabbit-staged-batch.md, then exits 2 (blocked).
#    User runs /coderabbit-fix which reads the staged batch and runs full triage.
#
# 2. Individual finding paste: detects any of:
#    - "Verify each finding against" (with or without "the current code")
#    - "Inline comments:" / "Outside diff comments:" / "Nitpick comments:" headers
#    - coderabbit-instructions sentinel
#    Injects triage rubric into context (exits 0). Claude rates and routes inline.
#
# Rating 3 deferred findings accumulate in ~/.claude/coderabbit-deferred.md
# for the current session only. On first detection per session the file is
# truncated and a session header is written; subsequent prompts append.
# The stop hook prints a reminder if deferred items exist at session end.
#
# Session change log: ~/.claude/coderabbit-session-log.md tracks every fix
# applied by the surgeon this session. Injected into context on each prompt
# so Claude can pass prior-change context to subsequent surgeon invocations.

set -euo pipefail

DEFERRED="$HOME/.claude/coderabbit-deferred.md"
SESSION_LOG="$HOME/.claude/coderabbit-session-log.md"
STAGED="$HOME/.claude/coderabbit-staged-batch.md"
STAMP_DIR="$HOME/.claude"

JQ=""
for _jq_candidate in jq /opt/homebrew/bin/jq /usr/local/bin/jq "$HOME/.local/bin/jq"; do
	if command -v "$_jq_candidate" &>/dev/null 2>&1; then
		JQ="$_jq_candidate"
		break
	fi
done
if [[ -z "$JQ" ]]; then
	exit 0
fi

input=$(cat)
prompt=$(echo "$input" | "$JQ" -r '.prompt // empty')
session_id=$(echo "$input" | "$JQ" -r '.session_id // empty')

# ------------------------------------------------------------------
# Detect "fix all" batch: CodeRabbit's batch button produces a prompt
# with multiple findings, each preceded by a "Verify each finding against"
# line. A single paste has exactly one such line; a batch has two or more.
# Count occurrences, two or more means it is a batch.
# ------------------------------------------------------------------
verify_count=$(echo "$prompt" | grep -c 'Verify each finding against' 2>/dev/null || true)
if [[ "$verify_count" -ge 2 ]]; then
	finding_count=$(echo "$prompt" | grep -c 'Verify each finding against' || true)
	{
		echo "# CodeRabbit Staged Batch"
		echo "# Staged: $(date '+%Y-%m-%d %H:%M')"
		echo "# Findings: ${finding_count}"
		echo ""
		echo "$prompt"
	} >"$STAGED"
	cat >&2 <<BLOCK
[CodeRabbit triage: batch staged]

${finding_count} finding(s) written to ~/.claude/coderabbit-staged-batch.md.
"Fix the following issues" bypasses the triage rubric -- run /coderabbit-fix
to process each finding through rating (1-5) and surgeon delegation.
BLOCK
	exit 2
fi

# ------------------------------------------------------------------
# Individual finding paste or file-based format: inject triage rubric
# ------------------------------------------------------------------
if echo "$prompt" | grep -qE 'Verify each finding against|coderabbit-instructions|Inline comments:|Outside diff comments:|Nitpick comments:'; then
	# On first CodeRabbit prompt in this session, reset the deferred file and session log
	stamp="$STAMP_DIR/.coderabbit-session"
	last_session=$(cat "$stamp" 2>/dev/null || echo "")
	if [[ "$last_session" != "$session_id" ]]; then
		echo "$session_id" >"$stamp"
		{
			echo "# CodeRabbit Deferred Findings"
			echo "# Session: $session_id"
			echo "# $(date '+%Y-%m-%d %H:%M')"
			echo ""
		} >"$DEFERRED"
		{
			echo "# CodeRabbit Session Change Log"
			echo "# Session: $session_id"
			echo "# $(date '+%Y-%m-%d %H:%M')"
			echo ""
		} >"$SESSION_LOG"
	fi

	# Inject prior session changes if any fixes have been applied this session
	log_entries=0
	if [[ -f "$SESSION_LOG" ]]; then
		log_entries=$(grep -c '^## fix-' "$SESSION_LOG") || log_entries=0
	fi
	if [[ "$log_entries" -gt 0 ]]; then
		echo "[CodeRabbit session context -- prior changes this session]"
		cat "$SESSION_LOG"
		echo ""
	fi

	cat <<'EOF'
[CodeRabbit triage active]

Context steps -- run these BEFORE rating any finding:
  1. Read the affected file around the reported line to understand local context.
  2. Grep for the affected symbol or function name across the codebase to identify
     callers, importers, and related files.
  3. Check the session change log above (if present). If prior fixes touch the same
     file or a related symbol, factor that accumulated state into your rating and
     into what you pass to the surgeon.

Rating:
  1-2  False positive or nitpick -- dismiss, one-line rationale, no edit.
  3    Judgment call -- do NOT fix; append finding + your assessment to
       ~/.claude/coderabbit-deferred.md; report "Deferred: <one-line summary>".
  4-5  Real defect -- spawn the code-surgeon agent to apply the fix.
       Use subagent_type "general-purpose", description "Fix CR-<N>: <one-line summary>".

When spawning the surgeon for a 4-5 finding, the prompt MUST include:
  - The finding location (file and line) and the expected fix.
  - Any prior session changes from the log that touch the same file or a related symbol.
  - The list of caller/importer files identified in context step 2, if any.

After each surgeon fix returns, append to ~/.claude/coderabbit-session-log.md:
  ## fix-<N>
  File: <path> (lines <range>)
  Change: <one-line description>
  Finding: CR-<N>
  Related files checked: <caller files or "none">

Do not fix inline. Do not spawn any other agent type.
EOF
fi

exit 0
