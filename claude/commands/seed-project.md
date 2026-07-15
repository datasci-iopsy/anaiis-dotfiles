Initialize Claude memory files for the current project.

Run `bash ~/.claude/scripts/seed-memory.sh` from the project root. This creates
`~/.claude/projects/<encoded-path>/memory/` with two starter files, project-tier
only; user-level preferences already live in the global tier
(`~/.claude/memory/`, git-synced) and are not seeded per project:

- `MEMORY.md`, index
- `project_current_phase.md`, active workstreams (update manually)

Skips files that already exist. Safe to re-run.
