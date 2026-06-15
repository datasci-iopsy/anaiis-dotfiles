---
name: environment
description: Local environment assumptions, macOS, Bash, direnv, uv, Claude wrapper PATH, and ~/.bashrc.local conventions
---

# Environment

- macOS, Bash shell. Shell config is user-managed and not tracked in dotfiles. Machine-local non-secret vars (GCP project, aliases) go in `~/.bashrc.local`, which is not tracked in git. `web-verify` is available via `export PATH="$HOME/anaiis-dotfiles/bin:$PATH"` in shell config. Never modify `.zshrc`.
- `direnv` manages per-project env vars via `.envrc`, loads automatically on cd.
- Secrets are never stored in JSON settings files and never globally exported from shell config. They live in one of three tiers: (1) the CLI's own credential store (`gh auth login`, `coderabbit auth login`, `postman login`); (2) cross-project env vars in `~/.config/secrets/global.env` (chmod 600), loaded only by projects whose `.envrc` includes `dotenv ~/.config/secrets/global.env`; (3) project-specific vars in that project's `.envrc`. Claude uses a secret only when the user names the variable; permission deny rules and the bash-guard hook block reading or dumping them.
- `uv` manages Python versions. Check `.python-version` before assuming the Python version.
- When working in projects with worktrees, confirm which worktree/directory you're in before running commands.
- Any hook or script that computes the repo root from its own path must resolve `BASH_SOURCE[0]` through `realpath` before the `dirname`/`cd` walk. `~/.claude/hooks/` and `~/.claude/scripts/` are always symlink layers into the repo; without `realpath`, the walk lands at `~/` instead of the repo root. Pattern: `SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"; REPO_DIR="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"`.
