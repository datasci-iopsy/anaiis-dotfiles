---
name: spec-task-file-placement
description: Specs go in spec/ with date-based filenames, plans and tasks go in tasks/; never a bare SPEC.md in the project root
metadata:
  type: feedback
---

Specs go in `spec/` (or `specs/`) as `YYYY-MM-DD-<slug>.md`; plans and tasks go in `tasks/`.
Create the directory if absent; use the project root only when creation is blocked. Never
write a bare `SPEC.md` that a later spec would overwrite.

**Why:** a 2026-08-01 spec-driven-development run wrote `SPEC.md` to the repo root per the
skill's default; the user moved it to `spec/` and made this the standing default.

**How to apply:** check the project root for `spec/` and `tasks/` right before each spec
`Write`; an earlier same-session check lapsed once. If `spec/` is gitignored, that is
deliberate local scratch; do not commit it.
