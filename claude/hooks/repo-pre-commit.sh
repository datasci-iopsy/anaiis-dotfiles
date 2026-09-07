#!/usr/bin/env bash
# repo-pre-commit.sh -- stable dispatcher for repo pre-commit hooks
#
# Repos call this single file via their .git/hooks/pre-commit.
# When script paths change inside dotfiles, update only this file --
# all repos pick up the change automatically.
#
# Runs only the staged-file linters, so commits stay fast. The full test
# suite runs at pre-push via repo-pre-push.sh (SKIP_TESTS=1 git push to
# bypass).
#
# Stable path (repos reference this; never rename it):
#   bash "$HOME/.claude/hooks/repo-pre-commit.sh"
#
# Bypass flags:
#   SKIP_R_LINT=1     git commit  -- skip R format + lint entirely
#   SKIP_R_FORMAT=1   git commit  -- skip styler auto-format only (lintr still runs)
#   SKIP_LINTR=1      git commit  -- skip lintr check only (styler still runs)
#   SKIP_RUFF=1       git commit  -- skip Python lint
#   SKIP_JSON_LINT=1  git commit  -- skip JSON format check
#   SKIP_SHFMT=1      git commit  -- skip shell format check
#   SKIP_SQLFMT=1     git commit  -- skip SQL format check

set -euo pipefail

SCRIPTS="$HOME/.claude/scripts"

bash "$SCRIPTS/r-lint-staged.sh"
bash "$SCRIPTS/ruff-lint-staged.sh"
bash "$SCRIPTS/json-lint-staged.sh"
bash "$SCRIPTS/shfmt-lint-staged.sh"
bash "$SCRIPTS/sqlfmt-lint-staged.sh"
