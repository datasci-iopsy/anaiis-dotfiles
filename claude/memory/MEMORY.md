# Global Memory Index

Cross-project user-level facts (`user_*.md`, `feedback_*.md`, `reference_*.md`), delivered via `session-start-context.sh`. Project facts, secrets, handoffs belong elsewhere; see README's Memory section.

- [User profile](user_profile.md) -- who the user is, how they work, the I-O analysis lens
- [Spec/task file placement](feedback_spec_task_file_placement.md) -- specs in spec/ with date-based names, tasks in tasks/, root only as fallback
- [Verify agent-generated hashes](feedback_verify_agent_generated_hashes.md) -- agents can transpose a SHA character; cross-check before acting
- [rm -rf chained-operator confirmation](feedback_rmrf_chained_operator.md) -- never chain rm -rf with && onto the next command; bash-guard always asks
- [Concurrent-session git commits](feedback_concurrent_session_git_commits.md) -- verify branch and diff ownership before committing stop-hook-flagged changes
- [AgentField undeclared env vars](feedback_agentfield_undeclared_env_vars.md) -- af run persists only declared config vars; re-export undeclared ones each invocation
- [Style rules vs document voice](feedback_style_rule_document_voice.md) -- register rules (STE) govern Claude's prose, never a user-owned document's; carve out and flag
