# dotfiles project context

## Source of truth

This repo (`~/.dotfiles`) is the source of truth for all Claude Code config. Files under
`claude/` are symlinked into `~/.claude/` by `install.sh`. Always edit at the source path
inside this repo, never the symlink destination.

| Edit this (source, tracked) | Not this (symlink destination) |
|---|---|
| `~/.dotfiles/claude/settings.json` | `~/.claude/settings.json` |
| `~/.dotfiles/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `~/.dotfiles/claude/rules/*.md` | `~/.claude/rules/*.md` |
| `~/.dotfiles/claude/skills/` | `~/.claude/skills/` |
| `~/.dotfiles/claude/hooks/` | `~/.claude/hooks/` |
| `~/.dotfiles/bash/shared.bash` | (no symlink; sourced by `~/.bashrc.local`) |

## Shell config

`bash/shared.bash` is tracked here and syncs across machines via git pull.
`~/.bashrc` and `~/.bashrc.local` are real files per machine, not symlinked. Edit them
directly when machine-local changes are needed. To propagate a change to all machines,
put it in `bash/shared.bash`.

## Install

Run `install.sh` once on a new machine to create all symlinks. This also invokes `claude/scripts/install-dbt-skills.sh` to build the vendored dbt skills (see below).

## dbt skills (vendored via git submodule)

Six dbt-labs/dbt-agent-skills are vendored as a git submodule and built into `claude/skills/dbt-*/` on every `install.sh` run.

**Submodule location:** `vendor/dbt-agent-skills/` (pinned commit)
**Allow-list:** defined in `claude/scripts/install-dbt-skills.sh` in the `SKILLS=(...)` array
**Built artifacts:** `claude/skills/dbt-*/SKILL.md` (gitignored; rebuilt from submodule each install)

### What the installer does
For each skill in the allow-list:
1. Copies `vendor/dbt-agent-skills/skills/dbt/skills/<name>/SKILL.md` and applies three patches: prefixes `name` with `dbt-`, forces `user-invocable: true`, appends a soft-gate sentence to `description`.
2. Symlinks all sibling files/dirs (references, scripts) back to the submodule so upstream resource updates land for free.
3. Prunes any `dbt-*` dirs that were removed from the allow-list.

### Current allow-list
- `dbt-using-dbt-for-analytics-engineering`
- `dbt-running-dbt-commands`
- `dbt-adding-dbt-unit-test`
- `dbt-building-dbt-semantic-layer`
- `dbt-answering-natural-language-questions-with-dbt`
- `dbt-fetching-dbt-docs`

### Adding or removing a skill
Edit the `SKILLS=(...)` array in `claude/scripts/install-dbt-skills.sh` and re-run `install.sh`.

### Updating to a newer upstream commit
```
cd vendor/dbt-agent-skills && git fetch && git checkout <target-commit> && cd ../..
bash install.sh
```
Then re-run the Phase 2 smoke test (see install plan or dbt project CLAUDE.md).

### Soft-gate caveat
The `dbt_project.yml` gate in each skill's description is a model hint, not a hard engine constraint. Skills will appear in available-skills on every machine. Auto-trigger should refuse outside a dbt project; if it does not, escalate by appending a stricter refusal sentence to that skill's entry in `install-dbt-skills.sh`.
