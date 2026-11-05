---
name: spec-task-file-placement
description: Specs go in spec/<YYYY-MM-DD-name>/ and plans, todos, and decisions go in tasks/<YYYY-MM-DD-name>/ (slug folders); never a bare SPEC.md in the project root
metadata:
  type: feedback
---

Specs and tasks live in slug folders. A slug is `YYYY-MM-DD-<name>`. The spec is `spec/<slug>/<slug>.md`. Plans, todos, decisions, and summaries are `tasks/<slug>/<kind>-<name>.md`. Create the folder if absent. The user moves finished slugs into `_archive/`. Never write a bare `SPEC.md` at the repo root, and never write a flat file directly in `spec/` or `tasks/`. If `spec/` is gitignored, that is deliberate scratch; do not commit it. The full layout is in `rules/work-tracking.md`.

**Why:** the owner re-bucketed both folders by slug on 2026-11-05 to keep parallel streams traceable. This replaces the flat dated layout of 2026-08-01.

**How to apply:** check that the slug folder exists right before each spec or plan `Write`; an earlier same-session check lapsed once (2026-08-01). A worktree reaches the folders by absolute path.
