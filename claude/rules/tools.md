---
name: tools
description: Preferred CLIs (gh, jq, duckdb, gcloud, make, tmux) and the always-use-structured-output flag
---

# Tool Preferences

- Use `gh` for all GitHub operations (PRs, issues, checks, repo links, etc.), never raw curl to the API.
- Use `jq` for JSON processing in shell.
- Use `duckdb` CLI as the default engine for querying local parquet, CSV, JSON, and Excel files. Never load these into pandas for ad hoc analysis. Pass `-json` for machine-readable output.
- Use `gcloud` for GCP operations (read-only unless user confirms).
- Prefer `make` targets over raw commands when a Makefile exists.
- Use `tmux` for processes that are projected to take longer than 5 minutes
- Check for project and subdirectory CLAUDE.md files before starting work.
- When invoking CLIs that support structured output, always use their JSON or machine-readable flag. Never parse tabular stdout. Known flags: `gh` (`--json`), `gcloud` (`--format=json`), `bq` (`--format=json`), `dbt` (`--output json`), `duckdb` (`-json`). For any other CLI, check for a `--format`, `--output`, or `--json` flag before running and use it if available.
