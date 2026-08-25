# Global Memory Index

Cross-project user-level facts (`user_*.md`, `feedback_*.md`, `reference_*.md`), delivered via `session-start-context.sh` (SessionStart hook). Project-specific facts, secrets, and handoffs belong elsewhere; see README's Memory system section for the full architecture.

- [User profile](user_profile.md) -- who the user is, how they work, and the I-O psychologist analysis lens
- [Spec/task file placement](feedback_spec_task_file_placement.md) -- specs go in spec/ (date-based filenames), plans/tasks go in tasks/, root is fallback-only
- [Verify agent-generated hashes](feedback_verify_agent_generated_hashes.md) -- agents can transpose a hash/SHA character; cross-check before acting
- [rm -rf chained-operator confirmation](feedback_rmrf_chained_operator.md) -- never chain rm -rf on a disposable cache dir with && onto the next command; bash-guard always asks regardless of path safety
- [Concurrent-session git commits](feedback_concurrent_session_git_commits.md) -- user runs parallel sessions on the same repo; verify branch/diff relevance before committing stop-hook-flagged changes
