---
name: Shell Config File
description: Bash config uses a single shared file at ~/anaiis-dotfiles/bash/shared.bash; ~/.bashrc and ~/.bashrc.local are real per-machine files, not symlinks; never touch .zshrc
type: feedback
---

Bash configuration is managed by the dotfiles repo. Do not read or modify `.zshrc`.
**Structure:** `~/anaiis-dotfiles/bash/shared.bash` is the single tracked shared preferences file, sourced by `~/.bashrc.local`. Both `~/.bashrc` and `~/.bashrc.local` are real per-machine files (not symlinks, not tracked in git). Machine-local values (GCP project, API keys) go in `~/.bashrc.local`.
**Why:** User uses bash exclusively. Shared config is tracked in the dotfiles repo and synced across machines via git pull; machine-local config stays untracked.
**How to apply:** For changes that should apply on all machines, edit `~/anaiis-dotfiles/bash/shared.bash`. For machine-specific changes, edit `~/.bashrc.local` directly.
