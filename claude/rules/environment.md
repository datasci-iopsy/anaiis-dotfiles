---
name: environment
description: Local environment assumptions, macOS, Bash, direnv, pyenv, Claude wrapper PATH, and ~/.bashrc.local conventions
---

# Environment

- macOS, Bash shell. Shell config is user-managed and not tracked in dotfiles. Machine-local vars (GCP project, API keys, aliases) go in `~/.bashrc.local`, which is not tracked in git. The Claude wrapper at `~/.dotfiles/bin/claude` is on PATH via `export PATH="$HOME/.dotfiles/bin:$PATH"` in shell config. Never modify `.zshrc`.
- `direnv` manages per-project env vars via `.envrc`, loads automatically on cd.
- `pyenv` manages Python versions. Check `.python-version` before assuming Python version.
- Before modifying Python venvs or dependencies, identify all venvs in the project and confirm which is active. Never modify venv contents without mapping the environment first.
- When working in projects with worktrees, confirm which worktree/directory you're in before running commands.
