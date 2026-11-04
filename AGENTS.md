# dotfiles project context

## Source of truth

This repo (`~/anaiis-dotfiles`) is the source of truth for all Claude Code config. Files under
`claude/` are symlinked into `~/.claude/` by `install.sh`. Always edit at the source path
inside this repo, never the symlink destination.

| Edit this (source, tracked) | Not this (symlink destination) |
|---|---|
| `~/anaiis-dotfiles/claude/settings.json` | `~/.claude/settings.json` |
| `~/anaiis-dotfiles/claude/rules/*.md` | `~/.claude/rules/*.md` |
| `~/anaiis-dotfiles/claude/hooks/` | `~/.claude/hooks/` |
| `~/anaiis-dotfiles/bash/shared.bash` | (no symlink; sourced by `~/.bashrc`) |

## Instruction files

`AGENTS.md` is the only instruction file in this repo. No `CLAUDE.md` is tracked.
Claude Code reads `AGENTS.md` from version 2.1.277. `bootstrap-doctor.sh` checks the version.

Global instructions live in `claude/rules/` (file `context.md`).
Claude Code reads only the user-level `CLAUDE.md` file and the `~/.claude/rules/` folder at user scope.
The `rules/` folder loads with no setting.

## Shell config

Three-file hierarchy (none are symlinked; all machine-local except `shared.bash`):

| File | Tracked | Purpose |
|---|---|---|
| `bash/shared.bash` | Yes | All portable preferences: PATH, aliases, tool inits, prompt. Edit here to sync across machines. |
| `~/.bash_profile` | No | Entry point only. Sources `~/.bashrc`. Do not add config here. |
| `~/.bashrc` | No | Machine-specific wiring: sources `shared.bash`, machine extras, then `~/.bashrc.local`. |
| `~/.bashrc.local` | No (gitignored) | Secrets and machine-specific overrides (API keys, project IDs). Never re-source `shared.bash` here. |

## Install

Run `install.sh` once on a new machine. It links the Claude config into `~/.claude/`.
It also wires the PATH line and the `shared.bash` source line into `~/.bashrc`.
When `gh` uses the SSH protocol, it adds the GitHub host keys after it checks their fingerprints.
The new-machine steps are in `README.md`. To check a machine, run `bash claude/scripts/bootstrap-doctor.sh`.

## Skills

`anaiis-*` skills are served by the `datasci-iopsy/anaiis-plugins` marketplace (registered in `claude/settings.json` under `extraKnownMarketplaces`).

`dbt-*` skills are served by the `dbt-labs/dbt-agent-skills` marketplace (also registered under `extraKnownMarketplaces`). No local copies or submodule needed.
`claude/settings.json` enables no dbt plugin. A dbt project enables the plugins in its own settings, so their skills load only there.

`graphify` is served as `anaiis-data:graphify` from the same marketplace. The repo once held a graphify submodule and a virtual environment for it. Both were removed on 2026-07-05, and no local copy exists.

`ponytail` (marketplace `DietrichGebert/ponytail`) is the build-behavior layer. Its SessionStart hook injects the lazy-senior-dev ruleset into every session and subagent. `rules/behavioral.md` no longer carries code-size rules. `claude/settings.json` declares the plugin (`extraKnownMarketplaces.ponytail`, `enabledPlugins`). Its default level is `PONYTAIL_DEFAULT_MODE` in `bash/shared.bash`. `evals/ponytail/` holds the A/B suite that measured it.

## Worktrees

Worktrees live under `tmp/worktrees/<id>`. Git ignores `tmp/`, `tasks/`, and `spec/`. Those folders exist only in the main checkout.

Live config comes from the main checkout. The `~/.claude/*` links point at `~/anaiis-dotfiles/claude/`, and `install.sh` always resolves the main worktree as that canonical path.
A change in a worktree does not reach `~/.claude/` until it merges.

Test a worktree with a throwaway HOME. `tests/lib/fresh-home.sh` builds one whose `~/.claude` links point at the worktree under test.
All worktrees share one `.git/hooks` folder. Test hook scripts only in a throwaway repo, never in the real one.

Project memory is per worktree path. The project key comes from the working directory, so each worktree has its own project tier.
