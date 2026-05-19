# dotfiles project context

## Source of truth

This repo (`~/anaiis-dotfiles`) is the source of truth for all Claude Code config. Files under
`claude/` are symlinked into `~/.claude/` by `install.sh`. Always edit at the source path
inside this repo, never the symlink destination.

| Edit this (source, tracked) | Not this (symlink destination) |
|---|---|
| `~/anaiis-dotfiles/claude/settings.json` | `~/.claude/settings.json` |
| `~/anaiis-dotfiles/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `~/anaiis-dotfiles/claude/rules/*.md` | `~/.claude/rules/*.md` |
| `~/anaiis-dotfiles/claude/hooks/` | `~/.claude/hooks/` |
| `~/anaiis-dotfiles/bash/shared.bash` | (no symlink; sourced by `~/.bashrc`) |

## Shell config

Three-file hierarchy (none are symlinked; all machine-local except `shared.bash`):

| File | Tracked | Purpose |
|---|---|---|
| `bash/shared.bash` | Yes | All portable preferences: PATH, aliases, tool inits, prompt. Edit here to sync across machines. |
| `~/.bash_profile` | No | Entry point only. Sources `~/.bashrc`. Do not add config here. |
| `~/.bashrc` | No | Machine-specific wiring: sources `shared.bash`, machine extras, then `~/.bashrc.local`. |
| `~/.bashrc.local` | No (gitignored) | Secrets and machine-specific overrides (API keys, project IDs). Never re-source `shared.bash` here. |

## Install

Run `install.sh` once on a new machine to create all symlinks. Also provisions the graphify Python environment (see below).

## Skills

`anaiis-*` skills are served by the `datasci-iopsy/anaiis-plugins` marketplace (registered in `claude/settings.json` under `extraKnownMarketplaces`).

`dbt-*` skills are served by the `dbt-labs/dbt-agent-skills` marketplace (also registered under `extraKnownMarketplaces`). No local copies or submodule needed.

`graphify` is still vendored locally in `vendor/graphify/` (a git submodule) with its Python environment in `vendor/graphify-venv/`. The skill lives in `claude/skills/graphify/`. This will be migrated to marketplace-only delivery once the graphify upgrade workstream is complete.
