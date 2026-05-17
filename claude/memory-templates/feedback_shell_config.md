---
name: Shell Config File
description: Bash config is modular under ~/anaiis-dotfiles/bash/bashrc.d/, never touch .zshrc, and do not treat .bash_profile as the edit target
type: feedback
---

Bash configuration is modular and managed by the dotfiles repo. Do not read or modify `.zshrc`.
**Structure:** `~/.bash_profile` is a thin loader (symlink) that sources `~/.bashrc` (also a symlink). All real config lives in `~/anaiis-dotfiles/bash/bashrc.d/` numbered module files, with OS-specific overrides in `os-darwin.bash` / `os-linux.bash`. Machine-local values (GCP project, API keys) go in `~/.bashrc.local` (not tracked in git).
**Why:** User uses bash exclusively. Config was modularized for dotfiles management and cross-platform support.
**How to apply:** To add or change shell config, identify the correct module file (e.g., `09-aliases-git.bash` for git aliases, `04-path.bash` for PATH). Never write directly to `~/.bash_profile` or `~/.bashrc`, they are symlinks and edits would be lost. For machine-specific changes, edit `~/.bashrc.local`.
