# Agents

This directory is wired as `~/.claude/agents/` via a directory-level symlink. Claude Code
scans it for globally-discoverable named agents.

It is currently empty. Agents are intentionally not stored here.

**Why:** skill-specific agents (code-surgeon, coderabbit-triage, intent-verifier) belong
to the skill that defines their inputs and outputs. They are governed by plugin versioning
and live in the plugin cache after install. Placing copies here creates a second source of
truth that drifts silently.

**When to add something here:** only for a truly cross-skill, cross-project agent whose
contract is not tied to any specific skill's input format. That does not currently exist.
