# Global Claude Instructions

## Behavioral rules

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.

For rationale and cross-links, see `rules/behavioral.md`.

This file provides project context and author identity. Detailed rules live in `~/.claude/rules/`.

## Project context
Research and data science workflows (I-O Psychology). Primary languages: R, Python, SQL.
Cloud: GCP (BigQuery, gcloud). Version control: GitHub via `gh` CLI.

## Author identity
Git author is set via `GIT_AUTHOR_NAME` / `GIT_COMMITTER_NAME` in `~/.claude/settings.json`.
The `attribution.commit` field controls Co-Authored-By trailers only, not the commit author.

## Rules and skills

Rules (`~/.claude/rules/`) constrain Claude's behavior across all tasks. Skills (`~/.claude/skills/`) add task-specific workflow steps within those constraints. When they conflict, rules take precedence.

## Rules index
| File | Covers |
|---|---|
| `rules/behavioral.md` | The 4 lines: surface tradeoffs, minimum code, touch only what you must, verify before claiming done |
| `rules/environment.md` | macOS, Bash, direnv, pyenv, worktree safety |
| `rules/tools.md` | gh, jq, gcloud, make, structured CLI output |
| `rules/code-style.md` | Writing style, shell formatting, no emojis |
| `rules/git.md` | Branch naming, commit discipline, staging |
| `rules/r-conventions.md` | Vectorization, lapply/vapply, lintr style |
| `rules/python.md` | uv, direnv, ruff |
| `rules/session.md` | Token efficiency, context thresholds, output prefs, compaction |
| `rules/core.md` | Simplicity, root causes, workflow, sub-agents |
| `rules/duckdb.md` | DuckDB query discipline: purpose-based patterns, no re-querying context |
| `rules/citations.md` | Citation integrity: corpus-only sources, no fabrication, web search only on explicit request |
| `rules/dashboards.md` | Dashboard data provenance, manifest discipline, narrative-data alignment, audience language |

## Machine-local overrides
`~/.claude/CLAUDE.local.md` (gitignored), machine-specific environment notes.

## Memory tiers
Two tiers, both per-machine, both auto-loaded:
- **Global tier** at `~/.claude/memory/`, cross-project user-level facts (identity, preferences). Loaded once per session via the `load-global-memory.sh` UserPromptSubmit hook.
- **Project tier** at `~/.claude/projects/<project-key>/memory/`, project-specific facts. The project's `MEMORY.md` index loads natively. Session handoffs live in the `handoffs/` subdirectory (rolling cap of 5, ISO-timestamped).
Run `bash ~/.claude/scripts/memory-doctor.sh` to verify the pipeline end-to-end.
