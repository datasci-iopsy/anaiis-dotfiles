Install standard pre-commit hooks in the current git repository.

Run `bash ~/.claude/scripts/install-repo-hooks.sh` from the project root. This adds
R lint (`r-lint-staged.sh`) and Python lint/format (`ruff-lint-staged.sh`) to
`.git/hooks/pre-commit`. Safe to re-run, skips entries already present.

Bypass options (for emergency commits only):
- `SKIP_R_LINT=1 git commit ...`
- `SKIP_RUFF=1 git commit ...`
