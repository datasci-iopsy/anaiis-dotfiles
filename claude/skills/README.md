# Skills

Skills define task-specific workflows and load lazily, by description or by explicit `/name`. Rules (`~/.claude/rules/`) define always-on behavioral constraints and auto-load into every Claude Code session. Rules take precedence when they conflict with skill instructions.

Each skill is self-documented in its `SKILL.md`. Read those files directly.

## Adding a skill

1. Create `claude/skills/<name>/SKILL.md` with `name` and `description` frontmatter
2. Use `anaiis-` prefix for custom skills; retain upstream names for external skills
3. Marketplace skill sets (`anaiis-plugins`, `dbt-agent-marketplace`) are served via the plugin system registered in `claude/settings.json`; keep no local copies of them here.
4. Never duplicate rule content in a skill, reference the relevant rule file instead
