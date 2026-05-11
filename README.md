# dotfiles

**What this is.** A personal Claude Code policy stack, rules, skills, hooks, agents, slash commands, plus one shell-agnostic Claude wrapper. Tracked in git, shared across two machines (personal + work), installed via symlinks in `install.sh`. macOS today; portable to Linux.

**It does not manage your shell config.** The previous bash layer was deleted in the 2026-04-29 audit. The only shell-adjacent piece left is `bin/claude`, a standalone POSIX script you opt into by adding one directory to `$PATH`. Your `~/.bashrc` / `~/.zshrc` / `~/.config/fish/config.fish` is yours.

**The "anaiis-" prefix** is the namespace for this repo's custom skills, distinct from upstream Anthropic skills (which keep their unprefixed names). When you see `/anaiis-litreview` or `/anaiis-duckdb`, that's a custom skill defined in `claude/skills/`.

**Two-machine model.** The same repo is checked out on personal and work machines. Machine-local config, secrets, project IDs, GCP project, lives in two files that `install.sh` *copies* (not symlinks) on first install:

- `~/.claude/settings.local.json`, model override, machine-local Claude settings
- `~/.claude/CLAUDE.local.md`, machine-local environment notes

Both are gitignored from this repo by virtue of being outside it. Your shell config and any other machine-local secrets are your concern, not this repo's.

**Audit artifacts.** The current state of this repo is the result of a 5-advisor LLM Council audit on 2026-04-29. The full transcript, visual report, and remediation plan are archived in `_archive/`: `council-report-2026-04-29.html`, `council-transcript-2026-04-29.md`. They explain *why* the structure looks the way it does.

**Install in 60 seconds.**

```bash
git clone git@github.com:datasci-iopsy/.dotfiles.git ~/.dotfiles
bash ~/.dotfiles/install.sh
# Then add to your shell config (~/.bashrc, ~/.zshrc, etc.):
#   export PATH="$HOME/.dotfiles/bin:$PATH"
```

That installs the Claude policy stack and prints a one-line snippet to add to your shell config. No bash takeover, no source files, no machine-specific overrides forced on you.

---

## Directory structure

```
.dotfiles/
├── install.sh                      Symlinks claude/* into ~/.claude/; prints PATH snippet
├── README.md                       This file
├── .lintr                          → ~/.lintr   Global R style config
├── .env.example                    Structural template, this repo consumes nothing from .env
├── _archive/                       Non-tracked artifacts (council report, transcript, etc.)
├── bash/
│   └── shared.bash                 Shared bash helpers sourced by hook and test scripts
├── bin/
│   ├── claude                      Shell-agnostic CodeRabbit batch wrapper
│   └── web-verify                  CLI wrapper: serve + Playwright verify + teardown
├── claude/
│   ├── CLAUDE.md                   → ~/.claude/CLAUDE.md   Short index; rules live in rules/
│   ├── CLAUDE.local.md.template    Copy-once template for machine-local Claude notes
│   ├── settings.json               → ~/.claude/settings.json   Permissions, hooks, model, status line
│   ├── settings.local.json.template  Copy-once template for machine-local settings
│   ├── keybindings.json            → ~/.claude/keybindings.json   shift+enter / alt+enter = newline
│   ├── rules/                      → ~/.claude/rules/   Behavioral constraints (auto-loaded)
│   ├── commands/                   → ~/.claude/commands/   Custom slash commands
│   ├── skills/                     → ~/.claude/skills/   Custom skills (lazy-loaded by description)
│   ├── agents/                     → ~/.claude/agents/   Specialized sub-agents
│   ├── hooks/                      → ~/.claude/hooks/   Hook scripts (referenced by settings.json)
│   ├── scripts/                    → ~/.claude/scripts/   Utility scripts
│   └── memory-templates/           Templates copied per-project by seed-memory.sh
├── templates/
│   ├── dashboard/                  anaiis-dashboard: manifest validator, bootstrap.js, inline helper, Playwright spec
│   ├── playwright-plotly/          Plotly render template (render.py + index.html.tmpl)
│   ├── playwright-ggplot2/         ggplot2/htmlwidgets render template (render.R)
│   └── playwright-static/          Static HTML smoke test scaffold (package.json, playwright.config.ts)
└── tests/
    ├── bin-claude.sh               Phase-3 wrapper test harness (cross-shell, Linux-ready)
    ├── fixtures/                   Test fixture files
    ├── measure-userpromptsubmit.sh  Hook-latency measurement (run when chain grows)
    ├── test-claude-md-rules.sh     Validates CLAUDE.md rules index against rules/ on disk
    ├── test-compact-hooks.sh       PreCompact / PostCompact end-to-end test
    └── test-em-dash-guard.sh       Verifies block-em-dash.sh hook fires on U+2014 payloads
```

---

## Setup on a new machine

### 1. Clone

```bash
git clone git@github.com:datasci-iopsy/.dotfiles.git ~/.dotfiles
```

### 2. Run the installer

```bash
bash ~/.dotfiles/install.sh
```

Each line prints `ok` (already linked), `link` (newly created), or `SKIP` (real file present, back up and remove first). Two files are *copied* (not symlinked) as machine-local config and never overwritten on subsequent runs:

- `~/.claude/settings.local.json`, set `GITHUB_TOKEN`, override model, etc.
- `~/.claude/CLAUDE.local.md`, machine-specific environment notes

### 3. Add the wrapper to PATH (optional but recommended)

The installer prints this line; copy it into your shell config (one of `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, whichever your shell reads):

```bash
export PATH="$HOME/.dotfiles/bin:$PATH"
```

Open a new shell. `which claude` should now resolve to `~/.dotfiles/bin/claude`.

### 4. Per-project memory bootstrap

Run once from each project root you'll use Claude in:

```bash
cd /path/to/project
bash ~/.claude/scripts/seed-memory.sh
```

Then edit `~/.claude/projects/<encoded-path>/memory/project_current_phase.md`.

### 5. Repo pre-commit hooks

When working in Claude Code, hooks install automatically on the first prompt in any repo via `ensure-repo-hooks.sh`. For repos you commit to outside Claude (direct CLI commits, CI), run once from the project root:

```bash
bash ~/.claude/scripts/install-repo-hooks.sh
```

---

## The bin/claude wrapper

```
~/.dotfiles/bin/claude
```

A standalone POSIX bash script. When you put `~/.dotfiles/bin` ahead of the system `claude` in `$PATH`, this wrapper runs first and handles one job: detecting CodeRabbit "fix all" batches before they reach `claude` and stage to a deterministic file.

**Why a shell-level wrapper:** CodeRabbit's "Fix all" emits `claude "$(cat …tmpfile)" && rm …tmpfile`. In a fresh terminal, `direnv` startup latency causes CodeRabbit to retry, by which point the trailing `rm` has already deleted the tmpfile, leaving Claude with empty input. A Claude `PreToolUse` hook can't help, by then `claude` has already started.

**Behavior.** If the first arg contains ≥2 `Verify each finding against the current code` lines:

1. Stages the batch to `~/.claude/coderabbit-staged-batch.md`
2. Prints two notice lines to stdout
3. Execs the real `claude` with the batch arg shifted off, so the user can run `/coderabbit-fix` interactively

Otherwise, pass-through: the wrapper exec's the real `claude` with all args, unchanged.

**Verification.** `bash tests/bin-claude.sh` runs 12 deterministic assertions (13 when zsh is present) covering shebang/executable, bash and zsh PATH resolution, pass-through behavior, batch detection, resolver collision (wrapper skips non-executable `claude` earlier in PATH), and `install.sh` output shape.

---

## CodeRabbit workflow

### "Fix all" batch

1. Click "Fix all" in CodeRabbit. The terminal prints `[CodeRabbit] N finding(s) staged`.
2. Inside the Claude session, run `/coderabbit-fix`.
3. Step 0 reads the staged batch and runs each finding through full triage (rate → dismiss/defer/surgeon).
4. After the batch, step 1 picks up any previously deferred findings.

### Triage rubric

| Rating | Action |
|---|---|
| 1–2 | False positive or nitpick, dismiss with one-line rationale, no edit |
| 3 | Judgment call, append to `~/.claude/coderabbit-deferred.md`, report "Deferred: …" |
| 4–5 | Real defect, spawn `code-surgeon` agent (`Fix CR-<N>: …`), log to `~/.claude/coderabbit-session-log.md` |

### Files

| File | Purpose |
|---|---|
| `~/.claude/coderabbit-staged-batch.md` | Raw batch from "fix all"; read and deleted by `/coderabbit-fix` step 0 |
| `~/.claude/coderabbit-deferred.md` | Rating-3 findings; processed by step 1 |
| `~/.claude/coderabbit-session-log.md` | Change log injected into context on subsequent prompts |

---

## Skills, commands, rules, agents

### Skills (custom, lazy-loaded)

`anaiis-agents`, `anaiis-changelog`, `anaiis-copyedit`, `anaiis-dashboard`, `anaiis-docaudit`, `anaiis-duckdb`, `anaiis-gitpr`, `anaiis-gitrebase`, `anaiis-litreview`, `anaiis-peerreview`, `anaiis-preflight`, `anaiis-skillreview`, `anaiis-webverify`, `graphify` (14 total).

Skills with overlap against an Anthropic built-in declare a `built_in_alternative` field in their `SKILL.md` frontmatter explaining the differentiation (currently: `anaiis-changelog`, `anaiis-docaudit`).

See `claude/skills/README.md` for trigger conditions.

### Commands

| Command | What it does |
|---|---|
| `/seed-project` | Init per-project memory files from templates |
| `/install-hooks` | Install pre-commit lint dispatcher (R, Python, Shell, JSON) in a repo |
| `/coderabbit-fix` | Process CodeRabbit findings through triage; stages first, deferred second |

### Rules

| File | Covers |
|---|---|
| `rules/behavioral.md` | The 4 imperatives: surface tradeoffs, minimum code, touch only what you must, verify |
| `rules/environment.md` | macOS, Bash, direnv, pyenv, worktree safety |
| `rules/tools.md` | gh, jq, gcloud, make, structured CLI output flags |
| `rules/code-style.md` | Writing style, shell formatting, no emojis |
| `rules/git.md` | Branch naming, commit discipline, author identity |
| `rules/r-conventions.md` | Vectorization, lapply/vapply, lintr style |
| `rules/python.md` | uv, direnv, ruff |
| `rules/session.md` | Token efficiency, context thresholds, output preferences |
| `rules/duckdb.md` | DuckDB query discipline (purpose-based patterns) |
| `rules/citations.md` | Citation integrity (corpus-only sources, no fabrication) |
| `rules/core.md` | Simplicity, root causes, subagent discipline |
| `rules/dashboards.md` | Dashboard data provenance, manifest discipline, narrative-data alignment, audience language |

### Agents (Sonnet, restricted tools)

- `code-reviewer.md`, diff review (Read/Grep/Glob)
- `security-auditor.md`, credential and injection checks (Read/Grep/Glob)
- `code-surgeon.md`, surgical fixes from CodeRabbit triage (Read/Grep/Glob/Edit)

---

## Hooks

Configured in `claude/settings.json`. Scripts in `claude/hooks/`.

| Event | Matcher | Script | Behavior |
|---|---|---|---|
| `UserPromptSubmit` |, | `surface-behavioral-rules.sh` | Injects behavioral rules into the first prompt of each session |
| `UserPromptSubmit` |, | `maintenance-check.sh` | Weekly plan-file check; monthly session-storage check; weekly repo-hooks audit |
| `UserPromptSubmit` |, | `coderabbit-triage.sh` | CodeRabbit triage rubric injection for individual pastes |
| `UserPromptSubmit` |, | `ensure-repo-hooks.sh` | Silently installs pre-commit dispatcher in current repo if missing |
| `UserPromptSubmit` |, | `load-global-memory.sh` | Loads global memory tier (`~/.claude/memory/`) once per session |
| `PostToolUse` | `Edit\|Write` | `post-edit-lint.sh` | `.py` ruff; `.sh` shfmt (auto-fix) + shellcheck; `.sql` sqlfmt; `.R` lintr; `.json` jq --indent 4 |
| `PreToolUse` | `Write\|Edit\|MultiEdit\|NotebookEdit` | `block-em-dash.sh` | Rejects any payload containing U+2014 (em dash); enforces no-em-dash code style rule |
| `PreToolUse` | `Write\|Edit` | inline | Allow `*.env.example`/`*.env.template`; block `*.lock`, `*.env`, `*credentials*`, `*secret*`, `*.pem`, `*.key` |
| `PreToolUse` | `Bash` | inline | Block destructive `bq rm`, `gcloud delete*`, `uv cache clean`/`pip uninstall` |
| `PreToolUse` | `Bash` | `prefer-jq.sh` | Warns when Python is used for JSON instead of jq |
| `PreToolUse` | `Agent\|WebFetch` | `cost-guard.sh` | Cost tiering MEDIUM/HIGH/VERY HIGH; gates general-purpose agents |
| `Stop` |, | `stop-hook-git-check.sh` | Reports uncommitted changes; never blocks (status-only) |
| `PreCompact` | `*` | `pre-compact.sh` | Writes a structured handoff to project memory |
| `PostCompact` | `*` | `post-compact.sh` | Re-injects the handoff so Claude has continuity post-compaction |
| `StatusLine` | n/a | `statusline-command.sh` (in `scripts/`) | Custom status line display in the Claude Code UI |

Hook latency on this machine (measured 2026-04-29, before `surface-behavioral-rules.sh` was added): aggregate UserPromptSubmit chain median = **98 ms** (under 100 ms target). Re-measure with `bash tests/measure-userpromptsubmit.sh` if the chain grows.

---

## Shell / R / SQL / Python style enforcement

| Language | Edit-time | Commit-time | Bypass |
|---|---|---|---|
| **Shell** | `post-edit-lint.sh` auto-applies `shfmt -w -i 0 -bn -ci` | `shfmt-lint-staged.sh` blocks | `SKIP_SHFMT=1 git commit …` |
| **R** | `post-edit-lint.sh` runs `lintr` and reports | `r-lint-staged.sh` blocks if violations | `SKIP_R_LINT=1 git commit …` |
| **SQL** | `post-edit-lint.sh` auto-applies `sqlfmt` (line_length=120, jinja-aware) | not enforced | n/a (auto-fix only) |
| **Python** | `post-edit-lint.sh` runs `ruff check` (reported) + `ruff format` (auto-applied) | `ruff-lint-staged.sh` blocks | `SKIP_RUFF=1 git commit …` |
| **JSON** | `post-edit-lint.sh` enforces `jq --indent 4` | `json-lint-staged.sh` checks indent | n/a |

`~/.lintr` is symlinked from this repo (`.lintr`). Per-project `.lintr` overrides are honored, lintr walks up from the project root.

---

## Memory system

Per-project memory at `~/.claude/projects/<encoded-path>/memory/`. Each project memory dir contains an auto-indexed `MEMORY.md` plus topical files (user/feedback/project/reference). Pre-compact and post-compact hooks write and restore session handoffs automatically.

Templates for new memory entries live in `claude/memory-templates/` (committed to this repo). Actual memory directories are per-machine and not tracked.

A global tier at `~/.claude/memory/` holds cross-project user-level facts (identity, preferences), loaded once per session by `load-global-memory.sh`. Templates live in `claude/memory-templates/global/`.

---

## Git author identity

Claude-driven commit authorship is set via env vars in `claude/settings.json`:

```json
"env": {
    "GIT_AUTHOR_NAME": "datasci-iopsy",
    "GIT_COMMITTER_NAME": "datasci-iopsy"
}
```

These override `git config`. The `attribution.commit` field (currently `""`) controls Co-Authored-By trailers only, it does not affect author name.

---

## Per-machine prerequisites

`install.sh` only handles symlinks. The following must be installed per machine:

```bash
brew install gh jq shellcheck shfmt ruff uv
uv tool install shandy-sqlfmt
```

The `graphify` skill is a Claude Code skill (not a uv tool). It auto-installs its Python dependency (`pip install graphifyy`) on first use via Step 1 of the skill. No manual install required.

R packages (global, not renv-managed):

```r
install.packages(c("lintr", "styler", "languageserver"))
```

---

## Adding new dotfiles

1. Move the file into `~/.dotfiles/<category>/`.
2. Add a `symlink` line to `install.sh`.
3. Run `install.sh` once to create the new symlink.
4. Commit and push.
