---
name: feedback_duckdb_cli
description: Always use the duckdb CLI for local file queries, never Python's duckdb module
metadata:
  type: feedback
---

Use `duckdb` CLI directly for all local CSV, parquet, JSON, and Excel queries. Never invoke Python's `duckdb` module or load data into pandas.

**Why:** The CLI is installed, already in PATH, and is the explicit rule in `rules/tools.md`. Using `uv run python -c "import duckdb..."` adds a dependency layer and fails when the module is not in the active venv.

**How to apply:** `duckdb -json -c "SELECT ... FROM read_csv_auto('path/to/file.csv')"`. Never reach for Python duckdb, pandas, or any other data loading layer for local files.
