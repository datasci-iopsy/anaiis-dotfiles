# Skills

Skills define task-specific workflows. Rules (`~/.claude/rules/`) define always-on behavioral constraints. Rules take precedence when they conflict with skill instructions. Both auto-load into every Claude Code session.

Each skill is self-documented in its `SKILL.md`. Read those files directly.

## Adding a skill

1. Create `claude/skills/<name>/SKILL.md` with `name` and `description` frontmatter
2. Use `anaiis-` prefix for custom skills; retain upstream names for external skills
3. For vendored upstream skill sets (e.g., dbt-labs/dbt-agent-skills), the installer (`claude/scripts/install-dbt-skills.sh`) manages naming, patching, and lifecycle. Do not manually place or rename these files; re-run `install.sh` instead.
4. Never duplicate rule content in a skill, reference the relevant rule file instead
