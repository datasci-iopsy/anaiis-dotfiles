# Spec: Memory Workflow Report

## Objective

Produce `reports/memory-workflow.qmd`: a diagram-first maintainer reference that maps every
component, trigger, file read/write, and dependency in the Claude Code memory system as
implemented in `anaiis-dotfiles`. The report is a pre-refactor audit artifact; precision
over narrative completeness.

**Target:** Sole maintainer. No onboarding context needed.

---

## Investigation scope

### Hooks (in scope: directly read or write memory files or session state)

| Hook | Trigger | Why in scope |
|------|---------|--------------|
| `claude/hooks/load-global-memory.sh` | UserPromptSubmit | reads global tier; writes session marker |
| `claude/hooks/surface-behavioral-rules.sh` | UserPromptSubmit | reads behavioral.md via script; writes session marker |
| `claude/hooks/pre-compact.sh` | PreCompact | writes handoff file to project memory tier |
| `claude/hooks/post-compact.sh` | PostCompact | reads handoff file from project memory tier |

### Scripts (in scope: called by memory hooks or operate on memory files)

- `claude/scripts/extract-behavioral-rules.sh` - called by `surface-behavioral-rules.sh`
- `claude/scripts/memory-doctor.sh` - diagnostic; exercises the full pipeline
- `claude/scripts/migrate-memory.sh` - moves memory between tiers
- `claude/scripts/seed-memory.sh` - initializes memory files for a new project

### Memory files and tiers

- **Global tier:** `~/.claude/memory/MEMORY.md` (index) + topical files (`user_*.md`, `feedback_*.md`, `reference_*.md`)
- **Project tier:** `~/.claude/projects/<project-key>/memory/MEMORY.md` + topical files + `handoffs/` subdir (rolling cap: 5)
- **Session markers:** `/tmp/claude-session-<id>.global-loaded`, `/tmp/claude-session-<id>.behavioral-loaded`
- **Harness native load:** project `MEMORY.md` is loaded automatically by Claude Code (not a hook)

### Settings

- `claude/settings.json` hooks block: hook registration per event type

### Out of scope

Hooks that do not read or write memory files:
`maintenance-check.sh`, `ensure-repo-hooks.sh`, `list-merged-claude-branches.sh`,
`block-em-dash.sh`, `block-edit-on-main.sh`, `block-sensitive-writes.sh`,
`block-destructive-commands.sh`, `prefer-jq.sh`, `cost-guard.sh`, `post-edit-lint.sh`,
`stop-hook-git-check.sh`

---

## Report structure

Sections in `reports/memory-workflow.qmd`, in order:

1. **System overview** - two-tier architecture; what is hook-injected vs. harness-native; 1 short paragraph
2. **Session lifecycle** - mermaid sequence diagram: session start through compaction to next session
3. **Hook inventory** - per hook: trigger event, reads, writes, exit behavior; one mermaid flowchart per hook
4. **File inventory** - per file type: location pattern, format, writer(s), reader(s)
5. **Dependency graph** - mermaid directed graph: hooks to scripts to files
6. **Session marker pattern** - first-prompt idempotency mechanism; `/tmp/` lifecycle and cleanup
7. **Compaction pipeline** - PreCompact event to PostCompact; handoff file format; rolling cap enforcement
8. **Harness native load** - what Claude Code loads automatically vs. what hooks inject; why the split exists

---

## Doc style

- Mermaid diagrams carry the visual load; every major flow has one
- Prose: 1-2 sentences per component; terse; direct statement of the "why"
- No "this is because" framing; no emojis
- Quarto `.qmd` with ` ```{mermaid} ` blocks
- Code blocks for file paths, command strings

---

## Verification standard

- Every file path verified against the live filesystem before documenting
- Every hook behavior read from source code, not inferred
- Every diagram edge traceable to a line in a hook or script
- No speculative documentation

---

## Boundaries

| Always | Ask first | Never |
|--------|-----------|-------|
| Read hook source before documenting its behavior | If a hook's behavior is ambiguous after reading | Document what hooks "probably" do without reading them |
| Verify file paths exist before including them | If a file exists on disk but is not referenced in any hook | Include out-of-scope hooks unless they directly touch a memory file |
| Note when a behavior is harness-native vs. hook-driven | | |
