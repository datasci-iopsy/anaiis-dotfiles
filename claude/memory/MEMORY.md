# Global Memory Index

Cross-project user-level facts that apply across every Claude session. Git-tracked in the dotfiles repo (`claude/memory/`) and symlinked to `~/.claude/memory`; syncs across machines via git. Loaded once per session (first prompt) by `~/.claude/hooks/load-global-memory.sh`.

What belongs here:
- User identity, role, preferences (`user_*.md`)
- Cross-project workflow rules and corrections (`feedback_*.md` that apply *anywhere*)
- Pointers to external systems usable from any project (`reference_*.md`)

What does NOT belong here:
- Anything specific to a single repo or codebase, that goes in `~/.claude/projects/<project-key>/memory/`
- Secrets, tokens, API keys (memory is not a secret store)
- Session handoffs (those live in the per-project `handoffs/` subdirectory)

Add an entry below for each topical file. Keep the index under 60 lines.

- [User profile](user_profile.md) -- who the user is and how they work; terse output, no push without instruction, audit before implementing
- [I-O Psychologist role](user_io_psychologist.md) -- I-O constructs, measurement theory, incremental analysis preference
- [Use jq not Python for JSON](feedback_jq_over_python.md) -- jq is the correct tool; inline Python scripts generate approval prompts
- [Agent token cost calibration](feedback_agent_token_cost.md) -- real Explore agent cost data; when parallelism is worth it
- [Memory workflow process](feedback_memory_workflow.md) -- three-tier update approach and what not to automate
- [Autocompact continuation](feedback_autocompact_continuation.md) -- at 85% context, /compact then resume automatically; hooks restore handoff; no re-orientation
- [No self-authorization](feedback_no_self_authorize.md) -- a question is never an instruction; wait for explicit confirmation before any edit, command, or branch
- [DuckDB CLI only](feedback_duckdb_cli.md) -- always use duckdb CLI for local file queries; never Python duckdb module or pandas
- [Investigate means read-only](feedback_investigate_means_readonly.md) -- investigate/analyze/determine = read-only; never probe unknown endpoints with real data; irreversible actions require explicit user instruction
