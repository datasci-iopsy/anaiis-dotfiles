---
name: agentfield-undeclared-env-vars
description: af run persists only declared package config vars; re-export undeclared vars on every invocation or they silently revert
metadata:
  type: feedback
---

`af config` and `af secrets` persist only variables declared in the node manifest (`af show-requirements <source>`). An undeclared variable reaches the node only from the ambient shell at that `af run` call and is lost on the next restart; `af config --list` never shows the gap.

**Why:** pr-af's undeclared `PR_AF_WORKDIR` defaulted to a read-only path and silently regressed after restarts (2026-09-01).

**How to apply:** before fixing an `af run` node, check declared vs undeclared; re-export undeclared fixes inline on every `af run`.
