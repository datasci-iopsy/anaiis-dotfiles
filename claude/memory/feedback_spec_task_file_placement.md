---
name: spec-task-file-placement
description: Spec and task/plan files belong in spec/ and tasks/ directories (auto-created), with date-based spec filenames, never a bare SPEC.md in project root
metadata:
  type: feedback
---

When writing a spec (spec-driven-development skill, Phase 1) or a plan/task list
(planning-and-task-breakdown, Phase 2-3), always search for an existing `spec/` or `specs/`
directory in the project root first (and `tasks/` for plan/task files). Create the directory
if it does not exist. Only fall back to writing the file directly in the project root if
directory creation is blocked or unavailable (a hook denies it, permissions fail), and only
then.

Spec filenames must be date-based so multiple specs can coexist, be identified, and audited
over time: `<spec-dir>/YYYY-MM-DD-<short-slug>.md` (for example,
`spec/2026-08-01-rabbit-sweep-rebase-retro.md`), not a bare `SPEC.md` that a later spec would
silently overwrite or force into a single-spec-per-project model.

**Why:** on 2026-08-01, a spec-driven-development run in `anaiis-plugins` wrote `SPEC.md` to
the repo root per the skill's literal default instruction. The user moved it to
`spec/SPEC.md` afterward and asked that this become the standing default going forward:
specs belong in a dedicated, discoverable directory, not the root, and a fixed filename can't
support more than one spec existing at a time.

**How to apply:** before writing a new spec file, `Glob`/`ls` the project root for `spec/` or
`specs/` (prefer whichever already exists in the repo; default to `spec/` if neither does).
Create it if absent, then write to `<dir>/<date>-<slug>.md`. Apply the same pattern to
`tasks/plan.md` and `tasks/todo.md` from the Plan/Tasks phases: check for `tasks/` in the
project root, create if missing, and only place at root if directory creation is blocked.
This applies across any project using the spec-driven-development or
planning-and-task-breakdown skills, not just `anaiis-plugins`.

**Gitignore check, don't assume commit-ability:** before treating "commit the spec" (a
step the spec-driven-development skill itself recommends) as automatic, run
`git check-ignore -v <spec-dir>` or check `.gitignore`. If the directory is already
gitignored, that's a deliberate repo convention (specs as local scratch, not shipped repo
content), not a bug to fix. Respect it silently rather than proposing to un-ignore it; just
note in the session summary that the spec exists locally but isn't tracked. Confirmed in
`anaiis-plugins` on 2026-08-01: `spec/` was already gitignored there pre-existing this
change, and the user chose to keep it that way rather than un-ignore it.
