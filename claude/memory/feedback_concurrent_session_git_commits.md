---
name: concurrent-session-git-commits
description: Before autonomously committing "pending" uncommitted changes flagged by the stop hook, verify they belong to the current session, not a concurrent session on the same repo
metadata:
  type: feedback
---

The user runs multiple Claude Code sessions concurrently against the same repo/branch. An
uncommitted diff sitting in the working tree when `stop-hook-git-check.sh` fires is not
necessarily "pending work from my logical unit" per [[git-workflow]] (`rules/git.md`); it can
belong to a different, live session doing unrelated deliberate work.

Confirmed once in `mattermoreai/dbt` (2026-08-18): a coherent, well-formed pending diff got
committed under the assumption it was this session's own work, when it actually belonged to a
concurrent session, on a branch whose name didn't even match the diff's topic.

**Why:** committing another session's mid-flight work under the umbrella of "the stop hook
said uncommitted changes" can interleave two unrelated logical concerns into one commit
history entry, and risks committing something the other session isn't done editing yet.

**How to apply:** when `stop-hook-git-check.sh` reports `[git] uncommitted changes`, before
committing: (1) run `git branch --show-current` fresh, never trust a stale `gitStatus`
snapshot; (2) compare `git diff` against what this session actually did. A mismatch on either
is a signal another session owns the diff; ask before committing instead of assuming.
