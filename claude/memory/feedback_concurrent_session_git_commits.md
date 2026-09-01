---
name: concurrent-session-git-commits
description: Before autonomously committing "pending" uncommitted changes flagged by the stop hook, verify they belong to the current session, not a concurrent session on the same repo
metadata:
  type: feedback
---

The user runs multiple Claude Code sessions concurrently against the same repo/branch. An
uncommitted diff when `stop-hook-git-check.sh` fires is not necessarily this session's own
pending work per [[git-workflow]] (`rules/git.md`); it can belong to a different, live
session doing unrelated work.

**Why:** confirmed once in `mattermoreai/dbt` (2026-08-18): a well-formed diff got
committed as this session's own when it actually belonged to a concurrent session, on a
branch whose name didn't even match the diff's topic. Interleaves unrelated concerns into
one commit and risks committing something not yet finished.

**How to apply:** when `stop-hook-git-check.sh` reports `[git] uncommitted changes`, before
committing: (1) run `git branch --show-current` fresh, never trust a stale `gitStatus`
snapshot; (2) compare `git diff` against what this session actually did. A mismatch on either
is a signal another session owns the diff; ask before committing instead of assuming.
