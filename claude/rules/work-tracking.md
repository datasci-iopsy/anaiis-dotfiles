---
name: work-tracking
description: Slug layout for spec/ and tasks/, file names per kind, stream files, the _archive folders, agent skill default paths, worktree access, and the todo item format
---

# Work Tracking

Specs, plans, task lists, and decision logs live in two folders at the root of the main checkout: `spec/` and `tasks/`. Git ignores both. Each piece of work has one slug. Every file for it sits in the folder of that slug.

## Slug

- A slug is `YYYY-MM-DD-<name>`. The date is the day of the first write. `<name>` is 2 to 5 lowercase words joined by hyphens.
- One slug covers one deliverable. A second deliverable gets a second slug.
- `<name>` is the slug without the date. File names inside a folder use `<name>`. Only the spec file repeats the date.

## Layout

```
spec/<slug>/<slug>.md
tasks/<slug>/plan-<name>.md
tasks/<slug>/todo-<name>.md
tasks/<slug>/decisions-<name>.md
tasks/<slug>/summary-<name>.md
```

- Other kinds: `review-<topic>.md` and `live-run-<topic>.md`. A `pr-bodies/` subfolder holds `pr<N>-<topic>.md`.
- Evidence files (scripts, run output) sit beside them in the same folder.
- Parallel streams: each stream owns `todo-<id>-<stream>.md` and `decisions-<id>-<stream>.md`. `<id>` is a letter or a short code. The master `todo-<name>.md` lists the streams. The worktree id of a stream is `<id>-<stream>`.
- Never write a flat file directly in `spec/` or `tasks/`. Never write a bare `SPEC.md` at the repo root.

## Archive

`spec/_archive/` and `tasks/_archive/` hold finished slugs. The user moves a slug there. Claude never moves a slug into `_archive/`, never writes there, and reads there only when the user names the slug.

## Finding the active slug

1. Use the slug that the user names.
2. Else use the slug whose `<name>` matches the description of the current branch.
3. Else, when exactly one slug outside `_archive/` exists, use it.
4. Else ask which slug. Never guess.

## Agent skill default paths

Agent skills name default paths. Use the slug path instead, and tell the skill where the file is.

| Skill default | Slug path |
|---|---|
| `SPEC.md`, `docs/SPEC.md`, or a file under `spec/` | `spec/<slug>/<slug>.md` |
| `tasks/plan.md` | `tasks/<slug>/plan-<name>.md` |
| `tasks/todo.md` | `tasks/<slug>/todo-<name>.md` |

A file under `spec/<slug>/` meets the check "a file under `spec/`" of `/build auto`.

## Worktrees

`spec/` and `tasks/` exist only in the main checkout (see `rules/git.md`, section "Worktree or branch in place"). From a worktree, read and write them by absolute path.
The main checkout is the parent of `git rev-parse --path-format=absolute --git-common-dir`. A worker writes only its own stream files.

## Todo item format

```
- [ ] T-1 Title
  evidence: <command result or file path>
```

Tick the box only when the `evidence:` line holds a command result or a file path.
