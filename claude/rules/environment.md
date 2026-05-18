---
name: environment
description: Local environment assumptions, macOS, Bash, direnv, pyenv, Claude wrapper PATH, and ~/.bashrc.local conventions
---

# Environment

- macOS, Bash shell. Shell config is user-managed and not tracked in dotfiles. Machine-local vars (GCP project, API keys, aliases) go in `~/.bashrc.local`, which is not tracked in git. `web-verify` is available via `export PATH="$HOME/anaiis-dotfiles/bin:$PATH"` in shell config. Never modify `.zshrc`.
- `direnv` manages per-project env vars via `.envrc`, loads automatically on cd.
- `pyenv` manages Python versions. Check `.python-version` before assuming Python version.
- Before modifying Python venvs or dependencies, identify all venvs in the project and confirm which is active. Never modify venv contents without mapping the environment first.
- When working in projects with worktrees, confirm which worktree/directory you're in before running commands.
- Any hook or script that computes the repo root from its own path must resolve `BASH_SOURCE[0]` through `realpath` before the `dirname`/`cd` walk. `~/.claude/hooks/` and `~/.claude/scripts/` are always symlink layers into the repo; without `realpath`, the walk lands at `~/` instead of the repo root. Pattern: `SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"; REPO_DIR="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"`.
