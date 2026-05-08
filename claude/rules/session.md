---
name: session
description: Token efficiency and output discipline, read-once policy, scoped reads with offset/limit, dedicated tools over Bash equivalents
---

# Session Discipline and Output Preferences

## Token efficiency

### Before reading any file
Check whether that file path already appears in a prior Read result in this session. If it does, use that content, do not call Read again. A prior Read result is sufficient even if you did not retain every line; reference what you have and state what is missing if needed.

### Read scope
- **Config and settings files:** read only the section relevant to the current task. Use offset/limit to target it. Read the full file only when understanding the file's full structure is the explicit task.
- **Files over 200 lines:** always use offset/limit. Estimate the relevant section before reading. If uncertain, use Grep first to locate the line range.
- **New files (never read this session):** use Glob or Grep to confirm existence and locate the relevant section before calling Read.

### Tool discipline
- Use Grep (not Bash grep/rg) and Glob (not Bash find/ls) for all search. Never use Bash(grep), Bash(rg), Bash(find).
- Never use Bash(cat), Bash(head), or Bash(tail), use Read with offset/limit.
- Chain independent read-only shell commands with `&&` in a single Bash call.
- Prefer Read over Bash(cat) unless piping to another command (e.g., `cat file | jq`).

## Session discipline
- One deliverable per session. If scope shifts (e.g., planning to implementation), ask whether to continue or start fresh.
- Auto-compact is enabled and fires at ~80–85% context. The user prefers to compact manually before auto-compact triggers. When context approaches 80%, stop any long-running process and flag it, do not push past the threshold.
- The PreCompact hook writes a timestamped handoff file and PostCompact restores it; compacting mid-session is safe and preserves continuity.
- When context is high, prefer writing output to a file over long in-context responses.
- Do not re-explore what was already explored in this session. Summarize prior findings from context.

## Output preferences

Output tier is determined by the nature of the task, not by whether a skill is running.

- **Terse** (default): confirmations, status updates, progress, summaries, simple changes, operational actions. 1–3 sentences. Skills that perform operations (git, PR, rebase, code fixes, preflight, DuckDB ad hoc) stay terse.
- **Standard**: when a change is non-obvious or has tradeoffs worth naming. A short paragraph or a few bullets, no prose padding.
- **Deliverable**: when the output itself is the product, research synthesis, manuscript review, copyedits, knowledge graphs, skill reviews, doc audits. Write to a file, not terminal. Skills in this tier: anaiis-litreview, anaiis-peerreview, anaiis-copyedit, anaiis-docaudit, anaiis-skillreview, graphify.
- **anaiis-changelog** is standard tier: its output is structured inline text for copy-paste into a PR description, not a file deliverable.

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
