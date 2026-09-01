---
name: spec-task-file-placement
description: Spec and task/plan files belong in spec/ and tasks/ directories (auto-created), with date-based spec filenames, never a bare SPEC.md in project root
metadata:
  type: feedback
---

Specs (spec-driven-development Phase 1) and plans/tasks (planning-and-task-breakdown Phase
2-3) go in `spec/`/`specs/` and `tasks/` respectively, created if absent. Fall back to the
project root only if directory creation is blocked. Spec filenames are date-based:
`<spec-dir>/YYYY-MM-DD-<short-slug>.md`, never a bare `SPEC.md` that a later spec would
overwrite.

**Why:** a 2026-08-01 spec-driven-development run wrote `SPEC.md` to repo root per the skill's
literal default; the user moved it to `spec/SPEC.md` and asked this become the standing
default.

**How to apply:** `Glob`/`ls` the project root for `spec/`/`specs/` right before every spec
`Write`, don't rely on an earlier same-session check (this lapsed once despite one). Same
check applies to `tasks/`.

**Gitignore check:** before treating "commit the spec" as automatic, check `.gitignore`. An
already-gitignored `spec/` is deliberate (local scratch, not shipped); respect it silently.
