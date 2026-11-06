---
name: context
description: Project context, author identity, rule precedence, machine-local rule files, the two memory tiers, and the Postman CLI note
---

# Context

Claude Code loads every file in `~/.claude/rules/` by itself. This file holds the facts that no other rule file owns.

## Project context

The work is research and data science for I-O Psychology. The primary languages are R, Python, and SQL.
The cloud platform is GCP (BigQuery and `gcloud`). Version control is GitHub through the `gh` CLI.

## Build scope

The ponytail plugin sets how much code Claude writes. Its SessionStart hook injects its ruleset into every session and subagent.
`settings.json` declares the plugin under `extraKnownMarketplaces` and `enabledPlugins`. The shell variable `PONYTAIL_DEFAULT_MODE` sets the level.
The `/ponytail` command reports or changes the level for one session. `rules/behavioral.md` covers authorization, process, and reporting.

## Rules and skills

Rules constrain Claude's behavior for all tasks. Skills (`~/.claude/skills/`) add workflow steps for one kind of task, inside the limits that rules set.
If a rule and a skill conflict, the rule wins.

## Author identity

The `env` block of `~/.claude/settings.json` sets `GIT_AUTHOR_NAME` and `GIT_COMMITTER_NAME`. These variables set the git author.
The `attribution.commit` field controls the Co-Authored-By trailer only. It does not set the commit author.

## Machine-local overrides

Machine-local shell config lives in `~/.bashrc.local`. Git does not track this file.

For machine-local Claude instructions, create the file `claude/rules/<name>.local.md` in the dotfiles repo.
`.gitignore` ignores `claude/rules/*.local.md`, so Git never tracks the file.
`~/.claude/rules/` links to `claude/rules/`, so Claude Code loads the file at session start.
Start the file with front matter that holds a `description:` line, because `rules-doctor.sh` checks every file in `claude/rules/`.
Claude Code does not read a user-level `settings.local.json`.

## Memory tiers

Two memory tiers exist. Both load automatically.

- The global tier is `~/.claude/memory/`. It holds cross-project facts about the user, such as identity and preferences.
  It is a local folder in each profile, not a link into the repo. It does not sync across profiles or machines. A memory plugin will take that over.
  The `session-start-context.sh` SessionStart hook loads it once at session start, and again after `/compact`, as `additionalContext`.
  Writes to it stay in the local folder. Git does not track them.
- The project tier is `~/.claude/projects/<project-key>/memory/`. It holds project facts for one machine.
  Claude Code loads the `MEMORY.md` index of the project natively.
  Claude Code derives `<project-key>` from the working directory, so each git worktree has its own project tier.
  Session handoffs live in the `handoffs/` subfolder. The folder keeps at most 5 files, and each file name holds an ISO timestamp.

Compaction targets 60% of context. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` in `shared.bash` sets the harness backstop to that threshold. See `rules/session.md`.
Run `bash ~/.claude/scripts/memory-doctor.sh` to verify the pipeline end to end.

## Postman CLI

Postman CLI is installed on this device. Use it for API Engineering work.
