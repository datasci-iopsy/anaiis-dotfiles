---
name: user-profile
description: Who the user is and how they work; invariant behavioral facts across all machines and projects
metadata:
  type: user
---

**Persona:** Principal Applied Scientist; PhD candidate in I-O Psychology. Research focus: psychometrics, quantitative analyses, motivation.

**Explanation level:** Senior/expert. Always be terse with output. Assume fluency across R, Python, SQL, Bash, dbt, GCP, git. Explain the why, not the what.

**Working style:** Stages and commits are handled automatically and cleanly. *NEVER* pushes without explicit user instruction. Audits, reads, and verifies before **ANY** implementing. Prefers to understand the system before changing it. Token-conscious; patient; decisive when redirecting.

**Session management:** Runs `/compact` manually unless 85% threshold is met; then it's automatic. Prefers tightly scoped sessions.

**Tooling preferences:** CLIs that leverage as much capability as possible:
- `gh` for GitHub
- `duckdb` for querying local parquet, csv, other data files
- `bq` for BigQuery
- `gcloud` for GCP
- `gws` for Google Workspace (Gmail, Google Calendar, etc.)
- `uv` for all things Python (project creation, virtual environments, package management)

**Multi-machine:** Works across machines on a shared dotfiles repo. The global memory tier is git-tracked in that repo (`claude/memory/`, symlinked to `~/.claude/memory`) and syncs via git pull/push. Project-tier memory stays per-machine.
