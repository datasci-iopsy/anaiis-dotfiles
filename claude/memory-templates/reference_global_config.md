---
name: Global Claude Config
description: Global settings.json and CLAUDE.md scope, set up via dotfiles
type: reference
---

Global config at `~/.claude/settings.json` and `~/.claude/CLAUDE.md` (symlinked from ~/anaiis-dotfiles/claude/).
**Why:** Avoids re-granting universal permissions per project and re-explaining preferences every session.
**How to apply:** Project settings.local.json only needs project-specific additions (e.g., poetry, project-specific scripts). Do not re-add globally permitted tools to project-local settings.

Key global permissions: Read, Write, git, python/python3, ls, tree, grep, find, cat, head, tail, wc, diff, sort, make, gh, jq, gcloud (read-only), WebSearch, WebFetch(docs.coderabbit.ai).
Global hook: PreToolUse guard blocks writes to *.lock, *.env, *credentials*, *secret*, *.pem, *.key.
