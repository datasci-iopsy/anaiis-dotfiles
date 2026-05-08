# Global Memory Index

Cross-project user-level facts that apply across every Claude session on this machine. Loaded once per session (first prompt) by `~/.claude/hooks/load-global-memory.sh`.

What belongs here:
- User identity, role, preferences (`user_*.md`)
- Cross-project workflow rules and corrections (`feedback_*.md` that apply *anywhere*)
- Pointers to external systems usable from any project (`reference_*.md`)

What does NOT belong here:
- Anything specific to a single repo or codebase, that goes in `~/.claude/projects/<project-key>/memory/`
- Secrets, tokens, API keys (memory is not a secret store)
- Session handoffs (those live in the per-project `handoffs/` subdirectory)

Add an entry below for each topical file. Keep the index under 60 lines.

- [User profile](user_profile.md), who the user is and how they work
