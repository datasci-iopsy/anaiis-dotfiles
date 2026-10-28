---
name: session
description: Token efficiency and output discipline, read-once policy, scoped reads with offset/limit, dedicated tools over Bash equivalents
---

# Session Discipline and Output Preferences

## Token efficiency

### Per-task token budget
Treat 4,000 tokens as a soft per-task budget. If a task is approaching that limit without reaching a natural checkpoint, summarize what has been done, what is verified, and what remains, then re-plan rather than pushing through. Surfacing the breach is better than silently overrunning it. The session-wide compaction threshold (60% context, see Session discipline below) is a separate, harder limit; the per-task budget is an earlier warning.

### Before reading any file
Check whether that file path already appears in a prior Read result in this session. If it does, use that content, do not call Read again. A prior Read result is sufficient even if you did not retain every line; reference what you have and state what is missing if needed.

### Before writing in a file
Read the file's current exports, the immediate caller of the function or section you are adding to, and any shared utilities referenced nearby. If the existing structure has no obvious rationale, ask before adding alongside it. "Looks orthogonal to me" is a dangerous assumption; the conflict may exist 30 lines away.

See also: `rules/behavioral.md` rule 3 (touch only what you must).

### Read scope
- **Config and settings files:** read only the section relevant to the current task. Use offset/limit to target it. Read the full file only when understanding the file's full structure is the explicit task.
- **Files over 200 lines:** always use offset/limit. Estimate the relevant section before reading. If uncertain, search first to locate the line range.
- **New files (never read this session):** search to confirm existence and locate the relevant section before calling Read.

### Tool discipline
- Search with the tools the session provides. On macOS and Linux, Claude Code omits the Glob and Grep tools by default and routes `find` and `grep` through Bash, where they run embedded `bfs` and `ugrep`; use those. When a session does provide Glob and Grep, prefer them. Never spawn an agent for a single search.
- Prefer Read with offset/limit for file contents. Bash `cat`, `sed -n`, `head`, or `tail` are fine when piping (`cat file | jq`) or when the session directs Bash-first work.
- Chain independent read-only shell commands with `&&` in a single Bash call.
- Subagents: reach for an Explore agent only when scope is genuinely uncertain or would span 4+ search tool calls; at most 2 in parallel; prefer sequential in plan mode. Never spawn an agent for file listing, a single-file read, or a targeted search (measured: a single broad Explore agent read 36 files for 58.7k tokens; 3 parallel Explore agents burned 24% of a weekly session before implementation began).

### CLI output discipline
Commands run as typed and print their full output. Limit the output yourself.

- **Routine commands** (status, list, build success): limit a long result with `head`, `tail`, or a narrow flag. Do not limit a short result.
- **Diagnostic output** (compile errors, test failures, stack traces): read all of it. Do not add a filter that could drop an error line.
- **Structured output** (`--json` flags): select the fields you need with `jq`.
- **Noisy commands** (dbt runs, long test suites): run them raw and rely on compaction hygiene.

## Session discipline
- One deliverable per session. If scope shifts (e.g., planning to implementation), ask whether to continue or start fresh.
- When the user corrects your approach, save a feedback memory before continuing.
- Compact at 60% context, not later. Models perform best in the 60-70% utilization band; the harness's own auto-compact previously defaulted to a ~85% backstop. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60` in `shared.bash` now sets that backstop itself to fire at 60%, measured against the active model's real context window (Claude Code defaults `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to the active model's max when unset, so this tracks correctly across Sonnet 5/Opus 5/Fable 5.1 at 1M and Haiku 4.5 at 200K without per-model tuning; leave the window var unset). `statusline-command.sh` writes the exact context percentage to a per-session file; `context-watch.sh` reads it and, at ≥55%, five points ahead of the harness's 60% trigger, emits a one-shot directive to finish the current step and state a one-sentence checkpoint, then continue; the automatic backstop compacts on its own, no manual `/compact` needed. The 5-point gap is deliberate: it guarantees the checkpoint directive lands before the harness's own backstop compacts, removing the race between the two mechanisms by construction rather than leaving them to compete at an identical threshold.
- On `/compact`, auto-continue from the restored handoff without re-orientation: do not ask "where were we?" or summarize the prior session. The PreCompact hook writes a timestamped handoff file; the SessionStart hook (`source: compact`) restores it as context immediately after compaction completes. Read the restored content, identify the item marked in progress, and execute it.
- When context is high, prefer writing output to a file over long in-context responses.
- Do not re-explore what was already explored in this session. Summarize prior findings from context.

## Output preferences

Output tier is determined by the nature of the task, not by whether a skill is running.

- **Terse** (default): confirmations, status updates, progress, summaries, simple changes, operational actions. 1–3 sentences. Skills that perform operations (git, PR, rebase, code fixes, preflight, DuckDB ad hoc) stay terse.
- **Standard**: when a change is non-obvious or has tradeoffs worth naming. A short paragraph or a few bullets, no prose padding.
- **Deliverable**: when the output itself is the product, research synthesis, manuscript review, copyedits, knowledge graphs, skill reviews, doc audits. Write to a file, not terminal. Skills in this tier: anaiis-litreview, anaiis-peerreview, anaiis-copyedit, anaiis-docaudit, anaiis-skillreview, graphify.
- **anaiis-git-ops:changelog** is standard tier: its output is structured inline text for copy-paste into a PR description, not a file deliverable.
- Register for every tier: ASD-STE100, per `rules/code-style.md`. Tiers set length; STE sets sentence and word construction.

Plan mode is its own context: comprehensiveness is appropriate regardless of tier, it exists to surface tradeoffs before committing to work.

- When asked "what did you do?", summarize in 2-3 bullet points. Offer detail only if the change was non-obvious.
- Write deliverable-tier output to a file, not terminal.

## Compaction instructions

These instructions are read by the compactor. When summarizing this conversation, preserve ALL of the following:

**Must preserve (verbatim or as a structured list):**
- The exact task being worked on and its acceptance criteria, specifically what "done" looks like
- Active git branch and worktree path
- Every file path read or modified this session, labeled by operation (Read / Write / Edit)
- Every decision made and the single-sentence reason behind it
- Every open error, blocker, or unresolved question
- Every mid-session behavioral override (e.g., "user said to skip X for this session")
- Every memory file written this session (path only)
- The filename of any handoff file written to memory/handoffs/ before this compaction (the pre-compact hook writes ISO-timestamped handoffs into that subdirectory; rolling cap of 5)

**Must not preserve (discard or one-line note only):**
- Full file contents, the file still exists on disk; the path is sufficient
- Tool call chains where only the conclusion matters
- Ruled-out approaches, one-line note only
- Acknowledgments, preamble, and intermediate reasoning steps

`/compact <prompt>` overrides these defaults.
