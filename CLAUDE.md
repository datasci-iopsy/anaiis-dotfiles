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

Run `install.sh` once on a new machine to create all symlinks.
