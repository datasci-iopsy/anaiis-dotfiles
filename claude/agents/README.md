# Agents

Named subagent type definitions for Claude Code. These are capability-bounded task agents, constrained tool sets, fixed models, specific scope.

This layer is distinct from the `anaiis-agents` skill:
- **This directory**: defines *what* named agents can do (tools, model, instructions)
- **`anaiis-agents` skill**: defines *when and how* to spawn agents dynamically during a session

Named agents here are invoked by the `coderabbit-fix` workflow. They are not general-purpose.

| Agent | Purpose | Tools |
|-------|---------|-------|
| `code-reviewer` | Review diffs or files for correctness, style, security | Read, Grep, Glob |
| `code-surgeon` | Apply a single CodeRabbit fix minimally | Read, Grep, Glob, Edit |
| `security-auditor` | Audit files or diff for security findings | Read, Grep, Glob |
