---
name: concurrent-session-git-commits
description: Before committing stop-hook-flagged changes, verify they belong to this session, not a concurrent session on the same repo
metadata:
  type: feedback
---

The user runs several Claude Code sessions on the same repo and branch. A diff flagged by `stop-hook-git-check.sh` may belong to another live session.

**Why:** a concurrent session's diff was committed as this session's own (mattermoreai/dbt, 2026-08-18).

**How to apply:** on `[git] uncommitted changes`, run `git branch --show-current` fresh and compare `git diff` with this session's edits. On any mismatch, ask before committing.
