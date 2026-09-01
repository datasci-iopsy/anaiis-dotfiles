---
name: agentfield-undeclared-env-vars
description: af run <node> only persists declared package config vars; undeclared vars must be re-exported on every single invocation or they silently revert
metadata:
  type: feedback
---

`af config`/`af secrets` only persist variables declared in a node's package manifest
(check `af show-requirements <source>`). An undeclared var only reaches the node via
ambient shell env at that exact `af run <node>` call, lost on every later restart that
doesn't re-export it; `af config --list` never reveals this gap.

**Why:** pr-af's undeclared `PR_AF_WORKDIR` defaults to `/workspaces` (read-only on bare
macOS). Cost three failed reviews (2026-09-01) to isolate, then regressed on restarts
that forgot to re-export it.

**How to apply:** before any `af run <node>` fix, check declared-vs-undeclared; re-export
undeclared fixes inline on every future `af run` call.
