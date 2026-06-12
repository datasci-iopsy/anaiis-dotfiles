# Global Claude Instructions

## Behavioral rules

Imperatives governing every task live in `rules/behavioral.md`, loaded natively with every file in `~/.claude/rules/`; count and wording authoritative in that file.

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
| `rules/behavioral.md` | Behavioral imperatives governing every task; count and wording authoritative in file |
| `rules/environment.md` | macOS, Bash, direnv, uv, worktree safety |
| `rules/tools.md` | gh, jq, gcloud, make, structured CLI output |
| `rules/code-style.md` | Writing style, shell formatting, no emojis |
| `rules/git.md` | Branch naming (`claude-<category>/<short-description>`), trivial-edit criteria, commits, push, PRs, worktrees for parallel work only |
| `rules/r-conventions.md` | Vectorization, lapply/vapply, lintr style |
| `rules/python.md` | uv, direnv, ruff |
| `rules/session.md` | Token efficiency, subagent limits, context thresholds, output prefs, compaction |
| `rules/duckdb.md` | DuckDB query discipline: purpose-based patterns, no re-querying context |
| `rules/citations.md` | Citation integrity: corpus-only sources, no fabrication, web search only on explicit request |
| `rules/testing.md` | Test-intent discipline: tests must encode why, not just what; fail-to-fail check |
| `rules/dashboards.md` | Dashboard data provenance, manifest discipline, narrative-data alignment, audience language |

## Machine-local overrides
`~/.claude/CLAUDE.local.md` (gitignored), machine-specific environment notes.

## Memory tiers
Two tiers, both auto-loaded:
- **Global tier** at `~/.claude/memory/`, cross-project user-level facts (identity, preferences). Git-tracked in the dotfiles repo (`claude/memory/`, symlinked by `install.sh`); syncs across machines via git. Loaded once per session via the `load-global-memory.sh` UserPromptSubmit hook. Writes to it land in the dotfiles working tree; commit them from a dotfiles session.
- **Project tier** at `~/.claude/projects/<project-key>/memory/`, project-specific facts, per-machine. The project's `MEMORY.md` index loads natively. Session handoffs live in the `handoffs/` subdirectory (rolling cap of 5, ISO-timestamped).
Run `bash ~/.claude/scripts/memory-doctor.sh` to verify the pipeline end-to-end.

@RTK.md
