---
name: git
description: Git workflow guardrails, branch verification, user-initiated commits and pushes, staging by name, no force-push, no --no-verify
---

# Git Workflow

## Before any push or commit suggestion
- Always run `git branch --show-current` before suggesting a push command. Never assume the branch. Surface the actual branch name in the suggestion.
- Always run `git status --short` before staging. Know what is changed before touching anything.

## User-initiated actions
- Commit and push are user-initiated actions. Stop hook messages about uncommitted or unpushed changes are status reports -- never commit or push in response to them without explicit user instruction.
- Never force-push. Never skip hooks (--no-verify).
- Never amend unless explicitly asked.

## Staging and commits
- Stage files by name, not `git add -A` or `git add .`.
- Always create new commits. One logical concern per commit.
- Commit messages: imperative mood, concise, no trailing period.

## Branches and PRs
- **Only** the user creates and owns feature branches (`<user-branch>`) that follow this convention (never create them):
  - `<type>/<linear-id>-<short-title>` (e.g., `feat/ana-758-engagement-survey`, `hotfix/dsio-33-auth-fix`)
  - `<type>/<short-title>` (e.g., `feat/engagement-survey`, `hotfix/auth-fix`)
- Claude always checks and branches from the user's feature branch (i.e., `<user-branch>/`). If no feature branch is detected, stop and notify the user. Claude branches always should follow the convention: 
  - `claude/<topic>` (e.g., `claude/ana-758-engagement-survey`)
- CodeRabbit triage is driven by `/anaiis-coderabbit` (the skill at `claude/skills/anaiis-coderabbit/SKILL.md`). Always run it from a `coderabbit/<topic>` or `claude/<topic>` branch; never from `main`. The skill enforces this as a hard stop in Phase 1.
- Never work directly on the user's feature branch. Always detect and create a Claude sub-branch first.
- Never push directly to main without explicit instruction.
- Never include session links (`https://claude.ai/code/session_*`) in PR titles, bodies, or descriptions. Sessions are deleted frequently and the links rot.

## Identity
- Git author identity is enforced via `GIT_AUTHOR_NAME`/`GIT_COMMITTER_NAME` in the harness `env` block (`~/.claude/settings.json`). The `attribution.commit` setting controls only `Co-Authored-By` trailers, not the author name.
