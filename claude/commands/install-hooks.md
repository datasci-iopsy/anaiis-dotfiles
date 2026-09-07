Install the standard repo hooks in the current git repository.

Run `bash ~/.claude/scripts/install-repo-hooks.sh` from the project root. This adds
two dispatcher hooks: `.git/hooks/pre-commit` runs the staged-file linters (R,
Python, Shell, JSON, SQL) and `.git/hooks/pre-push` runs the repo's
`tests/run-all.sh` when one exists. Safe to re-run: reports hooks already
present and adds `pre-push` to repos that only have `pre-commit`.

Bypass options (for emergency use only):
- `SKIP_R_LINT=1`, `SKIP_RUFF=1`, `SKIP_SHFMT=1`, `SKIP_SQLFMT=1 git commit ...`
- `SKIP_TESTS=1 git push ...`
