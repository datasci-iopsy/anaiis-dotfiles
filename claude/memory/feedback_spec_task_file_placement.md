---
name: spec-task-file-placement
description: Specs go in spec/ with date-based filenames, plans and tasks go in tasks/; never a bare SPEC.md in the project root
metadata:
  type: feedback
---

Specs go in `spec/` (or `specs/`) as `YYYY-MM-DD-<slug>.md`; plans and tasks go in `tasks/`. Create the directory if absent. Never write a bare `SPEC.md` at the repo root. If `spec/` is gitignored, that is deliberate scratch; do not commit it.

**How to apply:** check for `spec/` and `tasks/` right before each spec `Write`; an earlier same-session check lapsed once (2026-08-01).
