---
name: concurrent-session-git-commits
description: Before committing stop-hook-flagged uncommitted changes, verify they belong to this session, not a concurrent session on the same repo
metadata:
  type: feedback
---

The user runs several Claude Code sessions at once on the same repo and branch. An
uncommitted diff at `stop-hook-git-check.sh` time may belong to another live session, not
to this session's work per [[git-workflow]].

**Why:** in `mattermoreai/dbt` (2026-08-18) a diff from a concurrent session was committed
as this session's own, on a branch whose name did not match the diff's topic.

**How to apply:** on `[git] uncommitted changes`, run `git branch --show-current` fresh
(never trust the stale `gitStatus` snapshot) and compare `git diff` with what this session
did. On any mismatch, ask before committing.
