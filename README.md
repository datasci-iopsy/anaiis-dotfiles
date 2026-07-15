# dotfiles

**What this is.** A personal Claude Code policy stack, rules, skills, hooks, agents, slash commands, plus the `web-verify` CLI. Tracked in git, shared across two machines (personal + work), installed via symlinks in `install.sh`. macOS today; portable to Linux.

**Shell config.** `bash/shared.bash` is the tracked, portable shell config (PATH, aliases, tool inits, prompt). It is sourced by `~/.bashrc`, which is machine-local and not tracked. The wiring on each machine follows a three-file hierarchy: `~/.bash_profile` (entry point only, sources `~/.bashrc`) -> `~/.bashrc` (sources `shared.bash`, then `~/.bashrc.local`) -> `~/.bashrc.local` (secrets and machine overrides, gitignored). Never add config to `~/.bash_profile` directly; put portable things in `shared.bash` and machine-local secrets in `~/.bashrc.local`.

**The "anaiis-" prefix** is the namespace for this repo's custom skills, distinct from upstream Anthropic skills (which keep their unprefixed names). When you see `/anaiis-litreview` or `/anaiis-duckdb`, that's a custom skill defined in `claude/skills/`.

**Two-machine model.** The same repo is checked out on personal and work machines. `claude/settings.json` (symlinked to `~/.claude/settings.json`) is the single tracked source of truth for Claude Code config on both; Claude Code reads no user-level `settings.local.json` or `CLAUDE.local.md`, so this repo ships neither. Machine-local shell config and secrets live in `~/.bashrc.local` (untracked); secrets are environment variables loaded per-project via direnv (see `rules/environment.md`). Machine-local Claude instructions, when needed, are files under `~/.claude/` imported explicitly from `claude/CLAUDE.md` with `@~/.claude/<name>.md`.

**Audit artifacts.** The current state of this repo is the result of a 5-advisor LLM Council audit on 2026-04-29. The full transcript, visual report, and remediation plan are archived in `_archive/`: `council-report-2026-04-29.html`, `council-transcript-2026-04-29.md` (gitignored; exists only on machines where the audit was originally run). They explain *why* the structure looks the way it does.

**Install in 60 seconds.**

```bash
git clone --recurse-submodules git@github.com:datasci-iopsy/anaiis-dotfiles.git ~/anaiis-dotfiles
bash ~/anaiis-dotfiles/install.sh
# Then add to your shell config (~/.bashrc, ~/.zshrc, etc.):
#   export PATH="$HOME/anaiis-dotfiles/bin:$PATH"
```

That installs the Claude policy stack and prints a one-line snippet to add to your shell config. No bash takeover, no source files, no machine-specific overrides forced on you.

---

## Directory structure

```
anaiis-dotfiles/
├── install.sh                      Symlinks claude/* into ~/.claude/; prints PATH snippet
├── README.md                       This file
├── .lintr                          → ~/.lintr   Global R style config
├── .env.example                    Structural template, this repo consumes nothing from .env
├── bash/
│   └── shared.bash                 Shared bash helpers sourced by hook and test scripts
├── bin/
│   └── web-verify                  CLI wrapper: serve + Playwright verify + teardown
├── claude/
│   ├── CLAUDE.md                   → ~/.claude/CLAUDE.md   Short index; rules live in rules/
│   ├── settings.json               → ~/.claude/settings.json   Permissions, hooks, model, status line
│   ├── keybindings.json            → ~/.claude/keybindings.json   shift+enter / alt+enter = newline
│   ├── rules/                      → ~/.claude/rules/   Behavioral constraints (auto-loaded)
│   ├── commands/                   → ~/.claude/commands/   Custom slash commands
│   ├── skills/                     → ~/.claude/skills/   Custom skills (lazy-loaded by description)
│   ├── agents/                     → ~/.claude/agents/   Specialized sub-agents
│   ├── hooks/                      → ~/.claude/hooks/   Hook scripts (referenced by settings.json)
│   ├── scripts/                    → ~/.claude/scripts/   Utility scripts
│   └── memory-templates/           Project-tier templates copied by seed-memory.sh (MEMORY.md, project_current_phase.md)
├── templates/
│   ├── dashboard/                  anaiis-dashboard: manifest validator, bootstrap.js, inline helper, Playwright spec
│   ├── playwright-plotly/          Plotly render template (render.py + index.html.tmpl)
│   ├── playwright-ggplot2/         ggplot2/htmlwidgets render template (render.R)
│   └── playwright-static/          Static HTML smoke test scaffold (package.json, playwright.config.ts)
├── tests/
│   ├── fixtures/                   Test fixture files
│   ├── measure-memory-injection.sh  Memory injection overhead measurement
│   ├── measure-userpromptsubmit.sh  Hook-latency measurement (run when chain grows)
│   ├── run-all.sh                  Runs the full test suite
│   ├── SMOKE-TESTS.md              Manual smoke test scenarios
│   ├── test-bash-guard.sh          bash-guard.sh deny/allow assertions (destructive cmds, secrets path blocking, env-dump blocking, prefer-jq)
│   ├── test-block-sensitive-writes.sh   block-sensitive-writes.sh deny/allow assertions
│   ├── test-branching.sh           Trivial-edit criteria and branch-reuse logic
│   ├── test-claude-md-rules.sh     Validates CLAUDE.md rules index against rules/ on disk
│   ├── test-compact-hooks.sh       PreCompact handoff-writing end-to-end test
│   ├── test-context-watch.sh       context-watch.sh 60% directive emit/one-shot assertions
│   ├── test-cost-guard.sh          cost-guard.sh tiering, hard-block, and limit-override assertions
│   ├── test-em-dash-guard.sh       Verifies block-em-dash.sh hook fires on U+2014 payloads
│   ├── test-install-bashrc.sh      install.sh symlink and bashrc wiring assertions
│   ├── test-memory-doctor-guardrails.sh  Proves memory-doctor.sh checks I-M fail-then-pass
│   ├── test-memory-hooks.sh        Memory seed hook and marker-pruning assertions
│   ├── test-migrate-memory-guard.sh  migrate-memory.sh dry-run-default and template-stub-refusal assertions
│   ├── test-post-edit-lint-dispatch.sh  PostToolUse lint hook dispatch tests
│   ├── test-r-lint-staged.sh       r-lint-staged.sh assertions
│   ├── test-session-start-context.sh  session-start-context.sh additionalContext delivery assertions
│   ├── test-staged-lint-dispatch.sh     Pre-commit staged-lint hook dispatch tests
│   ├── test-statusline-context-bridge.sh  statusline pct-file write and 60% marker assertions
│   └── test-stop-hook-git-check.sh  stop-hook-git-check.sh exit-code assertions
└── vendor/
    └── graphify/                   git submodule (pinned to v7); source for /graphify skill
```

---

## Setup on a new machine

### 1. Clone

```bash
git clone --recurse-submodules git@github.com:datasci-iopsy/anaiis-dotfiles.git ~/anaiis-dotfiles
```

If you already cloned without `--recurse-submodules`, run this before Step 2:

```bash
cd ~/anaiis-dotfiles && git submodule update --init --recursive
```

### 2. Run the installer

```bash
bash ~/anaiis-dotfiles/install.sh
```

Each line prints `ok` (already linked), `link` (newly created), or `SKIP` (real file present, back up and remove first).

### 3. Add bin/ to PATH (required for web-verify)

The installer prints this line; copy it into your shell config (one of `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, whichever your shell reads):

```bash
export PATH="$HOME/anaiis-dotfiles/bin:$PATH"
```

This puts `web-verify` on your PATH. The old `bin/claude` CodeRabbit wrapper was removed in 2026-05-11; `which claude` now resolves to the real Homebrew-installed CLI.

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

## Memory system

Memory, compaction, and session history are three separate layers:

- **Memory files** (`claude/memory/` global tier, `~/.claude/projects/<key>/memory/` project tier): stable facts explicitly saved; persist across sessions; delivered to the model by `session-start-context.sh` (a SessionStart hook, matchers `startup|resume|clear|compact`) via `hookSpecificOutput.additionalContext`. This is the channel that actually reaches Claude, not `systemMessage`, which is display-only and never delivered to the model, a bug that went undetected for months before the 2026-07-15 memory-system review.
- **Compaction**: triggered manually (`/compact`) or automatically by the harness at ~85% context (a safety backstop, not the target; policy is to compact at 60%, see `rules/session.md`). The compactor summarizes the conversation itself and does not read memory files to decide what to keep.
- **Session history**: full JSONL transcript on disk, persists until pruned.

**Compaction continuity is a separate mechanism from compaction itself.** `pre-compact.sh` (PreCompact hook) writes a structured handoff file to the current project's `memory/handoffs/` subdirectory (rolling cap of 5) before compaction runs. `session-start-context.sh`, invoked again immediately after compaction completes (`source: compact`), restores the newest handoff as context. The compacted conversation summary itself does not carry this; the handoff file is what survives the boundary.

Templates for new project-tier memory entries live in `claude/memory-templates/` (committed to this repo). Project memory directories are per-machine and not tracked.

### Three-tier update process

**Tier 1, passive (zero cost):** Claude saves memories during sessions when it encounters something non-obvious (quirks, strategic decisions, user corrections). No trigger needed.

**Tier 2, end-of-session prompt (~5-10k tokens):** After sessions covering substantive work, end with: "Update memory with anything worth preserving from this session." Use for heavy sessions (100+ msgs, complex multi-file work); skip for routine sessions.

**Tier 3, manual for strategic context (no cost):** `project_current_phase.md` is maintained by the user, not Claude. Update it in a few sentences when a milestone is reached or focus shifts.

**Why:** A post-session memory agent would cost 20-50k tokens per run and most sessions don't produce new memories. The three-tier approach concentrates effort where it adds value.

---

## CodeRabbit workflow

CodeRabbit reviews are driven entirely from the terminal via the `/anaiis-coderabbit` skill. No VS Code paste, no wrapper script.

```bash
# From any non-main branch (after committing your work):
/anaiis-coderabbit
# Optional overrides:
/anaiis-coderabbit --base feat/my-branch --type committed
```

### What the skill does

1. Verifies auth (`coderabbit auth status --agent`) and that you are not on `main`.
2. Resolves the base branch and asks you to confirm scope before running.
3. Calls `coderabbit review --agent --base <base> --no-color` and captures NDJSON findings.
4. Triages each finding: skip 1-2 with logged rationale; fix 3-5 (severity 3 gets an extra cost-vs-benefit reasoning step before defaulting to fix).
5. Spawns `code-surgeon` for each fix, then verifies with formatters and project-detected tests.
6. Commits grouped fixes by logical concern (one finding per commit by default).
7. Re-runs the review to confirm all addressed findings are resolved.

### Triage rubric

| Severity | Action |
|---|---|
| 1-2 | Skip with one-sentence rationale; no edit |
| 3 | Read callers, weigh cost vs. benefit; default fix unless evidence says otherwise |
| 4-5 | Fix immediately; no extra reasoning needed |

All fixes run formatters and project-detected tests before committing. A fix that fails verification is reverted automatically.

### After triage

```
/anaiis-gitrebase   consolidate CR fix commits into logical groups
/anaiis-changelog   generate PR description from clean history
/anaiis-gitpr       open the PR
```

### Audit trail

Each session writes a JSONL ledger to `~/.claude/anaiis-coderabbit/runs/<branch>-<iso>.jsonl` with every triage decision, verification result, and commit event.

---

## Skills, commands, rules, agents

### Skills (custom, lazy-loaded)

`anaiis-agents`, `anaiis-changelog`, `anaiis-coderabbit`, `anaiis-copyedit`, `anaiis-dashboard`, `anaiis-docaudit`, `anaiis-duckdb`, `anaiis-gitpr`, `anaiis-gitrebase`, `anaiis-litreview`, `anaiis-peerreview`, `anaiis-preflight`, `anaiis-skillreview`, `anaiis-webverify`, `graphify` (15 registered; `anaiis-*` served from `datasci-iopsy/anaiis-plugins` marketplace, `graphify` vendored locally).

`dbt-*` skills are served via the `dbt-labs/dbt-agent-skills` marketplace (registered in `claude/settings.json` under `extraKnownMarketplaces`). They require no local files and do not appear in this repo.

Skills with overlap against an Anthropic built-in declare a `built_in_alternative` field in their `SKILL.md` frontmatter explaining the differentiation (currently: `anaiis-changelog`, `anaiis-docaudit`).

See `claude/skills/README.md` for trigger conditions.

### Commands

| Command | What it does |
|---|---|
| `/seed-project` | Init per-project memory files from templates |
| `/install-hooks` | Install pre-commit lint dispatcher (R, Python, Shell, JSON) in a repo |

### Rules

| File | Covers |
|---|---|
| `rules/behavioral.md` | The 9 imperatives: surface tradeoffs, minimum code, surgical changes, verify, model judgment scope, surface conflicts, fail loud, plan and checkpoint, hook output is not user input |
| `rules/environment.md` | macOS, Bash, direnv, uv, worktree safety |
| `rules/tools.md` | gh, jq, gcloud, make, structured CLI output flags |
| `rules/code-style.md` | Writing style, shell formatting, no emojis, convention conformance |
| `rules/git.md` | Branch naming (`claude-<category>/<short-description>`), trivial-edit criteria, commits, push, PRs, worktrees for parallel work only |
| `rules/r-conventions.md` | Vectorization, lapply/vapply, lintr style |
| `rules/python.md` | uv, direnv, ruff |
| `rules/session.md` | Token efficiency, subagent limits, context thresholds, output preferences |
| `rules/duckdb.md` | DuckDB query discipline (purpose-based patterns) |
| `rules/citations.md` | Citation integrity (corpus-only sources, no fabrication) |
| `rules/testing.md` | Test-intent discipline: tests must encode why, not just what; fail-to-fail check |
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
| `UserPromptSubmit` |, | `maintenance-check.sh` | Weekly plan-file check; monthly session-storage check; weekly repo-hooks audit |
| `UserPromptSubmit` |, | `ensure-repo-hooks.sh` | Silently installs pre-commit dispatcher in current repo if missing |
| `UserPromptSubmit` |, | `list-merged-claude-branches.sh` | Advisory: lists merged `claude/*` branches and shows the delete command |
| `SessionStart` | `startup\|resume\|clear\|compact` | `session-start-context.sh` | Delivers the global memory tier via `additionalContext` (startup/clear/compact); restores the newest pre-compact handoff (compact); advises `/seed-project` when the current project has no memory dir; delivery-gated monthly staleness advisory |
| `PostToolUse` | `Edit\|Write` | `post-edit-lint.sh` | `.py` ruff; `.sh` shfmt (auto-fix) + shellcheck; `.sql` sqlfmt; `.R` lintr; `.json` jq --indent 4 |
| `PostToolUse` | `*` | `context-watch.sh` | At >=60% context (read from the statusline's per-session pct file), emits a one-shot directive to checkpoint and request `/compact` |
| `PreToolUse` | `Write\|Edit\|MultiEdit\|NotebookEdit` | `block-em-dash.sh` | Rejects any payload containing U+2014 (em dash); enforces no-em-dash code style rule |
| `PreToolUse` | `Write\|Edit\|MultiEdit\|NotebookEdit` | `block-edit-on-main.sh` | Blocks all edits when the current branch is `main` or `master` |
| `PreToolUse` | `Write\|Edit` | `block-sensitive-writes.sh` | Allow `*.env.example`/`*.env.template`; block `*.lock`, `*.env`, `*credentials*`, `*secret*`, `*.pem`, `*.key` |
| `PreToolUse` | `Bash` | `bash-guard.sh` | Single guard: blocks destructive commands (`bq rm`, `gcloud delete*`, `uv cache clean`/`pip uninstall`), reads/writes to `.env`, credential paths (`.key`, `.pem`, `~/.aws/**`, `~/.config/gcloud/**`), shell rc files, and environment dumps (`printenv`/`echo $SECRET`); blocks Python for pure JSON parsing (jq's job) |
| `PreToolUse` | `Agent\|WebFetch` | `cost-guard.sh` | Cost tiering MEDIUM/HIGH/VERY HIGH; hard-blocks (exit 2) general-purpose agents above per-session cap (default 5, override via `COST_GUARD_GP_LIMIT`); blocks logged to `~/.claude/logs/cost-guard-blocks.log` |
| `Stop` |, | `stop-hook-git-check.sh` | Exits 2 (continues agent loop) on uncommitted changes, untracked files, or unpushed commits; exits 0 when clean |
| `PreCompact` | `*` | `pre-compact.sh` | Writes a structured handoff to project memory |
| `StatusLine` | n/a | `statusline-command.sh` (in `scripts/`) | Custom status line display; also bridges the exact context percentage to `context-watch.sh` via a per-session `/tmp` file |
| (in project repos) | n/a | `repo-pre-commit.sh` | Pre-commit dispatcher (R, Python, Shell, JSON) installed into repos by `install-repo-hooks.sh`; not a Claude Code hook |

Hook latency on this machine (measured 2026-07-15, 3-hook chain after the memory-delivery hooks moved to SessionStart): aggregate UserPromptSubmit chain median = **81 ms** (under 100 ms target). Re-measure with `bash tests/measure-userpromptsubmit.sh` if the chain grows.

---

## Shell / R / SQL / Python style enforcement

| Language | Edit-time | Commit-time | Bypass |
|---|---|---|---|
| **Shell** | `post-edit-lint.sh` auto-applies `shfmt -w -i 0 -bn -ci` | `shfmt-lint-staged.sh` blocks | `SKIP_SHFMT=1 git commit …` |
| **R** | `post-edit-lint.sh` runs `lintr` and reports | `r-lint-staged.sh` blocks if violations | `SKIP_R_LINT=1 git commit …` |
| **SQL** | `post-edit-lint.sh` auto-applies `sqlfmt` (line_length=120, jinja-aware) | `sqlfmt-lint-staged.sh` blocks | `SKIP_SQLFMT=1 git commit …` |
| **Python** | `post-edit-lint.sh` runs `ruff check` (reported) + `ruff format` (auto-applied) | `ruff-lint-staged.sh` blocks | `SKIP_RUFF=1 git commit …` |
| **JSON** | `post-edit-lint.sh` enforces `jq --indent 4` | `json-lint-staged.sh` checks indent | n/a |

`~/.lintr` is symlinked from this repo (`.lintr`). Per-project `.lintr` overrides are honored, lintr walks up from the project root.

---

## Usage report

Run at any time to see session counts, token totals (comma-formatted), agent spawn distribution, and cost-guard block counts. Add `--json` for raw integers suitable for `jq` pipelines or Claude audits:

```bash
bash ~/.claude/scripts/usage-report.sh --since 2026-05-01
bash ~/.claude/scripts/usage-report.sh --since 2026-04-01 --until 2026-04-30 --json
```

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

## Homebrew packages

A `Brewfile` at the repo root tracks all formulae, casks, and taps. Three commands cover the full lifecycle:

```bash
# New machine: install everything in the Brewfile
bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh install

# Check for drift (packages installed but not in Brewfile, or missing)
bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh check

# After installing something new: refresh the Brewfile and commit
bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh dump
git add Brewfile && git commit -m "chore: add <formula> to Brewfile"
```

`install.sh` prints the `install` command as a reminder but does not run it automatically (bundle install can take several minutes on a fresh machine and may prompt for sudo).

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

1. Move the file into `~/anaiis-dotfiles/<category>/`.
2. Add a `symlink` line to `install.sh`.
3. Run `install.sh` once to create the new symlink.
4. Commit and push.
