Initialize Claude memory files for the current project.

Run `bash ~/.claude/scripts/seed-memory.sh` from the project root. This creates
`~/.claude/projects/<encoded-path>/memory/` with seven starter files:

- `MEMORY.md`, index
- `user_profile.md`, role, expertise, interaction style
- `feedback_environment.md`, environment constraints
- `feedback_plan_mode.md`, plan vs. direct execution preferences
- `feedback_shell_config.md`, shell config path
- `reference_global_config.md`, global settings scope
- `project_current_phase.md`, active workstreams (update manually)

Skips files that already exist. Safe to re-run.
