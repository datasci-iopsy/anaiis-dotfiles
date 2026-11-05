---
name: environment
description: Local environment assumptions, macOS, Bash, direnv, uv, Claude wrapper PATH, and ~/.bashrc.local conventions
---

# Environment

- macOS, Bash shell. The harness (the Bash tool, the hooks, the status line) runs on Homebrew bash. `env.CLAUDE_CODE_SHELL` in `claude/settings.json` pins it, and `APPROVED_BASH_MAJORS` in `claude/scripts/bootstrap-doctor.sh` lists the approved majors. Shell config is user-managed and not tracked in dotfiles. Machine-local non-secret vars (GCP project, aliases) go in `~/.bashrc.local`, which is not tracked in git. `web-verify` is available via `export PATH="$HOME/anaiis-dotfiles/bin:$PATH"` in shell config. Never modify `.zshrc`.
- `direnv` manages per-project env vars via `.envrc`, loads automatically on cd.
- Secrets are never stored in JSON settings files and never globally exported from shell config. They live in one of three tiers: (1) the CLI's own credential store (`gh auth login`, `coderabbit auth login`, `postman login`); (2) cross-project env vars in `~/.config/secrets/global.env` (chmod 600), loaded only by projects whose `.envrc` includes `dotenv ~/.config/secrets/global.env`; (3) project-specific vars in that project's `.envrc`. Claude uses a secret only when the user names the variable; permission deny rules and the bash-guard hook block reading or dumping them.
- `uv` manages Python versions. Check `.python-version` before assuming the Python version.
- To delete a disposable path (`.ruff_cache`, `.venv`, `node_modules`, `__pycache__`, `dist`), issue `rm -rf <path>` as its own standalone Bash call. This is the simplest form, and `bash-guard.sh` allows it.
- If a command holds a recursive `rm` and a shell operator, `bash-guard.sh` allows it only when every statement is on a short vetted list. The list holds `rm`, `mkdir`, `cd`, `ls`, `echo`, `printf`, `pwd`, `true`, `false`, `test`, `[`, `basename`, and `dirname`. It also holds literal assignments and `for NAME in <literal words>` loops. It also holds the keywords `do`, `done`, `if`, `then`, `else`, and `fi`. Runners (`uv`, `make`, `python`, and similar) are not on the list. A child program of a runner can delete or create a path outside the guard. After a pipe, only `grep`, `head`, `tail`, `wc`, `cut`, `tr`, `basename`, and `dirname` are allowed. The statements join with `;`, `&&`, `||`, a newline, or a pipe. Two older carve-outs run before this check and allow with no guard. The first allows one recursive `rm` of a cache directory followed by runners such as `uv` or `make` (test 7a.9). The second allows `mktemp` assignments followed by a cleanup `rm` of those variables.
- For an allowed compound command, the hook runs `rm` and `mkdir` through `claude/hooks/safe-rm.sh`. The first use of each version of that file asks once. The rewritten command then writes a marker file, and later runs of that version do not prompt. If the harness does not apply the rewrite, no marker appears and every run asks. The script checks each expanded path. The roots are the session scratchpad, a disposable folder inside the working directory, `tests/fixtures/`, `tmp/` (except `tmp/worktrees`), and a `tmp.*` folder under `$TMPDIR`. Both `rm` and `mkdir` use these roots and change nothing else. `mkdir` allows only the flags `-p` and `-v`. The working-directory roots are off when the working directory is `$HOME`, a parent of `$HOME`, or `/`. It never deletes or creates `/`, `$HOME`, the working directory or a parent of it, or a path with a `.git` component. If one path is refused, it deletes or creates none, and the whole command stops: later statements do not run. A refusal could end only a subshell in four shapes, and the hook asks for each of them. These are an `rm`, an `mkdir`, a loop, or an `if` block on the left of a pipe; `$(...)`; a group in parentheses; and a background job.
- If the hook asks for confirmation, or `rm` prints `safe-rm: refused`, do not rewrite the command to avoid the check. Run the delete as its own call with a literal path. Inside the vetted-list check, a deletion word in any position of any statement makes the command ask: `rm` after the first word, `rmdir`, `find`, `xargs`, `eval`, `bash`, `sh`, `git`, `mv`, and similar. The two older carve-outs do not apply that rule. These also ask: a redirect to a file, `$(...)`, a backtick, `/bin/rm`, and `command rm`. A glob or single-quoted operand of `rm` asks. A loop variable or `printf -v` that names a guard variable asks. An alias that adds a flag outside the allowed set to `rm` or `mkdir`, such as `rm -i`, makes the function refuse by name. The rewritten command removes an alias of `rm` or `mkdir` that does not start with its own name, such as `command rm`, so the function always runs.
- When working in projects with worktrees, confirm which worktree/directory you're in before running commands.
- Any hook or script that computes the repo root from its own path must resolve `BASH_SOURCE[0]` through `realpath` before the `dirname`/`cd` walk. `~/.claude/hooks/` and `~/.claude/scripts/` are always symlink layers into the repo; without `realpath`, the walk lands at `~/` instead of the repo root. Pattern: `SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"; REPO_DIR="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"`.

## Configuration homes

Claude Code reads a value from a shell variable, from a key of a settings file, or from the `env` block of a settings file. The three do not rank the same way:

- A dedicated key loses to its shell variable. `ANTHROPIC_MODEL` beats the `model` key. `CLAUDE_CODE_EFFORT_LEVEL` beats the `effortLevel` key.
- For the model, the flag beats the variable: `--model` beats `ANTHROPIC_MODEL`. For effort, the variable beats `--effort` and `/effort`.
- An entry in the `env` block overwrites the same variable exported in the shell.

Place each value in the first home that fits:

| Order | The value is | Home | Reason |
|---|---|---|---|
| 1 | A secret | The credential tiers above | Settings files hold no secret |
| 2 | Machine-local (project IDs, local paths) | `~/.bashrc.local` | Git does not track it |
| 3 | Wiring that must hold in every launch path (the shell of the Bash tool and of the hooks) | The `env` block of `claude/settings.json` | The block applies however `claude` starts. It overwrites a stale shell value. |
| 4 | A dial that you change per task or per session (model, effort, output size, compaction level, timeouts, plugin level) | `bash/shared.bash`: an `export` for the default, an `alias` for each variant | The shell value beats the dedicated key. An alias overrides the export for one process. No file changes. |
| 5 | A preference with no shell variable (theme, tui, notifications), or structured config (hooks, permissions, plugins) | Keys in `claude/settings.json` | `/config` changes it on purpose. Commit it when you meant it. |

Rules:

- A name never appears in both `bash/shared.bash` (an `export` or an alias prefix) and the `env` block. The `env` value overwrites the shell value, so the shell value and every alias that sets it stop working. `rules-doctor.sh` check I.2 enforces this.
- `claude/settings.json` holds no `model`, `effortLevel`, or `modelSettings` key. `/model` and `/effort` write them into the symlinked file. Press `s` in the `/model` picker and in the `/effort` slider to apply a choice to the session only. `rules-doctor.sh` check I.1 enforces this.
- While `CLAUDE_CODE_EFFORT_LEVEL` is exported, `/effort` and `--effort` have no effect. Use an alias to change the effort for one launch.
- The git identity has no home in this table. Each machine sets `user.name` and `user.email` in its own git config. The `env` block sets no `GIT_AUTHOR_*` or `GIT_COMMITTER_*` variable, because a value there overrides the git config of every repo. `tests/test-rules-integrity.sh` (section 7) enforces this.
