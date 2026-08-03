# Global Memory Index

Cross-project user-level facts (`user_*.md`, `feedback_*.md`, `reference_*.md`), delivered via `session-start-context.sh` (SessionStart hook). Project-specific facts, secrets, and handoffs belong elsewhere; see README's Memory system section for the full architecture.

- [User profile](user_profile.md) -- who the user is, how they work, and the I-O psychologist analysis lens
- [rabbit-sweep code-surgeon Bash gap](feedback_rabbit_sweep_surgeon_bash.md) -- code-surgeon lacked Bash, produced a half-fixed mojibake bug; bypass subagent tool gaps instead of stopping
- [Spec/task file placement](feedback_spec_task_file_placement.md) -- specs go in spec/ (date-based filenames), plans/tasks go in tasks/, root is fallback-only
- [Verify agent-generated hashes](feedback_verify_agent_generated_hashes.md) -- agents can transpose a hash/SHA character; cross-check before acting
