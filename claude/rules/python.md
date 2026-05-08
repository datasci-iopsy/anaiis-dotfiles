---
name: python
description: Python project conventions, uv for versions and deps, direnv-managed venvs, ruff formatting; never invoke python directly
---

# Python Conventions

- `uv` manages Python versions and all project dependencies. Do not use `pyenv` for project Python, `pyenv` is installed via Homebrew but is not used for version pinning in projects.
- Every Python project uses `uv` with a `.python-version` file and `pyproject.toml`. The venv lives at `.venv/` in the project root.
- `direnv` activates the venv automatically on `cd`. Confirm `.envrc` sources `.venv` before assuming the environment is active. Never manually activate a venv when `direnv` is wired up.
- Before modifying any venv or dependencies, confirm which project root you are in and that `direnv` has loaded. Never run `uv` commands from the wrong directory.
- Always use `uv run` to execute Python scripts and tools. Never invoke `python`, `python3`, or `.venv/bin/python` directly.
- Formatting and linting are enforced by `ruff`. Run `ruff check --fix` then `ruff format` after edits. The pre-commit hook catches remaining drift.
- Per-project overrides live in `pyproject.toml` or `ruff.toml`; global defaults apply otherwise.
