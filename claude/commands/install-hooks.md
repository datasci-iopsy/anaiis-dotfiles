Install the standard repo hooks in the current git repository.

Run `bash ~/.claude/scripts/install-repo-hooks.sh` from the project root. This adds
three dispatcher hooks:
- `.git/hooks/pre-commit` runs the staged-file linters (R, Python, Shell, JSON, SQL).
- `.git/hooks/pre-push` runs the repo's `tests/run-all.sh` when one exists.
- `.git/hooks/commit-msg` checks the commit message against the house rubric.
  It checks only in a repo that has a `.conventional-commits` file at its root.

The script is safe to run again. It reports hooks that are already present
and adds any hook that is missing.

Bypass options (for emergency use only):
- `SKIP_R_LINT=1`, `SKIP_RUFF=1`, `SKIP_SHFMT=1`, `SKIP_SQLFMT=1 git commit ...`
- `SKIP_COMMIT_LINT=1 git commit ...`
- `SKIP_TESTS=1 git push ...`
