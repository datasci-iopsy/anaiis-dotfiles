# dotfiles

**What this is.** A personal Claude Code policy stack, rules, skills, hooks, agents, slash commands, plus the `web-verify` CLI. Tracked in git, shared across two machines (personal + work), installed via symlinks in `install.sh`. macOS today; portable to Linux.

**Shell config.** `bash/shared.bash` is the tracked, portable shell config (PATH, aliases, tool inits, prompt). It is sourced by `~/.bashrc`, which is machine-local and not tracked. The wiring on each machine follows a three-file hierarchy. The files load in this order: `~/.bash_profile` (entry point only, sources `~/.bashrc`) -> `~/.bashrc` (sources `shared.bash`, then `~/.bashrc.local`) -> `~/.bashrc.local` (secrets and machine overrides, gitignored). Never add config to `~/.bash_profile` directly; put portable things in `shared.bash` and machine-local secrets in `~/.bashrc.local`. `install.sh` writes the PATH line and the `shared.bash` source line into `~/.bashrc`. It does not add a line that sources `~/.bashrc.local`. Add that line yourself, after the `shared.bash` line, for example `[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"`. Without it, nothing loads `~/.bashrc.local`.

**Configuration homes.** Dials (model, effort, limits, plugin levels) live in `bash/shared.bash` as exports and aliases. Wiring that must hold in every launch path (the shell pin) lives in the `env` block of `claude/settings.json`. The git identity is not set here: each machine sets it in its git config (step 6 of "Setup on a new machine"). Preferences and structured config live in the other `settings.json` keys. A name never appears in both `shared.bash` and the `env` block, because the `env` value overwrites the shell value. `claude/settings.json` holds no `model`, `effortLevel`, or `modelSettings` key. `rules/environment.md` (section "Configuration homes") has the table and the reasons. `rules-doctor.sh` check I enforces two of its rules, and `tests/test-rules-integrity.sh` (section 7) enforces the rule for the git identity.

**Instruction files.** `AGENTS.md` is the only instruction file in this repo. No `CLAUDE.md` is tracked. The global instructions live in `claude/rules/context.md` and the other rule files, which Claude Code loads from `~/.claude/rules/`.

**The "anaiis-" prefix** is the namespace for the custom skills, distinct from upstream Anthropic skills (which keep their unprefixed names). They are served by the `datasci-iopsy/anaiis-plugins` marketplace registered in `claude/settings.json`; `claude/skills/` holds no copies of them.

**Two-machine model.** The same repo is checked out on personal and work machines. `claude/settings.json` (symlinked to `~/.claude/settings.json`) is the single tracked source of truth for Claude Code config on both. Claude Code reads no user-level `settings.local.json`, so this repo ships none. Machine-local shell config and secrets live in `~/.bashrc.local` (untracked); secrets are environment variables loaded per-project via direnv (see `rules/environment.md`). Machine-local Claude instructions, when needed, go in the file `claude/rules/<name>.local.md`. `.gitignore` ignores that file, and Claude Code loads it with the other rules (see `rules/context.md`).

**Audit artifacts.** The current state of this repo is the result of a 5-advisor LLM Council audit on 2026-04-29. The full transcript, visual report, and remediation plan are archived in `_archive/`: `council-report-2026-04-29.html`, `council-transcript-2026-04-29.md` (gitignored; exists only on machines where the audit was originally run). They explain *why* the structure looks the way it does.

**Install in 60 seconds.**

```bash
git clone git@github.com:datasci-iopsy/anaiis-dotfiles.git ~/anaiis-dotfiles
bash ~/anaiis-dotfiles/install.sh
```

That installs the Claude policy stack, wires `~/.bashrc`, and adds the GitHub host keys when `gh` uses SSH. Then follow steps 3 to 6 of "Setup on a new machine" below. Open a new terminal, start Claude Code once, run `/reload-plugins`, run the doctor, and set the git identity.

---

## Directory structure

```
anaiis-dotfiles/
├── install.sh                      Symlinks claude/* into ~/.claude/; wires the shell config; adds GitHub host keys
├── README.md                       This file
├── AGENTS.md                       Project instructions for Claude Code sessions in this repo
├── Brewfile                        Homebrew formulae, casks, taps; the daily refresh in shared.bash only adds entries
├── .conventional-commits           Opt-in marker: turns on the commit message lint in this repo
├── .github/workflows/tests.yml     CI: the test suite on macOS, then the bootstrap suites on bash 3.2
├── .lintr                          → ~/.lintr   Global R style config
├── .env.example                    Structural template, this repo consumes nothing from .env
├── bash/
│   └── shared.bash                 Tracked shell config (PATH, aliases, tool inits, prompt); also sourced by context-watch.sh and statusline-command.sh
├── bin/
│   └── web-verify                  CLI wrapper: serve + Playwright verify + teardown
├── evals/
│   └── ponytail/                   `claude plugin eval` suite for the ponytail plugin: run.sh, build-rules-prompt.sh, loc.sh, cases under evals/
├── reports/                        Measurement write-ups (the ponytail A/B report)
├── claude/
│   ├── settings.json               → ~/.claude/settings.json   Permissions, hooks, model, status line
│   ├── keybindings.json            → ~/.claude/keybindings.json   shift+enter / alt+enter = newline
│   ├── rules/                      → ~/.claude/rules/   Behavioral constraints and global context (auto-loaded; no index file)
│   ├── commands/                   → ~/.claude/commands/   Custom slash commands
│   ├── skills/                     → ~/.claude/skills/   Mount point for local and synced skills; anaiis-* skills come from the marketplace
│   ├── agents/                     → ~/.claude/agents/   Intentionally empty; skill agents live in the plugin cache
│   ├── hooks/                      → ~/.claude/hooks/   Hook scripts (referenced by settings.json)
│   ├── scripts/                    → ~/.claude/scripts/   Utility scripts (bootstrap-doctor.sh, brew-sync.sh, brew-share.sh, commit-msg-lint.sh, install-repo-hooks.sh, rules-doctor.sh, seed-memory.sh, usage-report.sh, lint-staged dispatchers)
│   ├── memory/                     → ~/.claude/memory/   Global memory tier (git-tracked, delivered at SessionStart)
│   └── memory-templates/           Project-tier templates copied by seed-memory.sh (MEMORY.md, project_current_phase.md)
├── templates/
│   ├── dashboard/                  anaiis-dashboard: manifest validator, bootstrap.js, inline helper, Playwright spec
│   ├── playwright-plotly/          Plotly render template (render.py + index.html.tmpl)
│   ├── playwright-ggplot2/         ggplot2/htmlwidgets render template (render.R)
│   └── playwright-static/          Static HTML smoke test scaffold (package.json, playwright.config.ts)
├── tests/
│   ├── fixtures/                   Test fixture files
│   ├── lib/                        Test helpers: fresh-home.sh (throwaway HOME), cov.sh (approximate line coverage from xtrace)
│   ├── e2e-git-identity.sh         Opt-in (`E2E=1`) check in real `claude -p` sessions that the settings env block leaves the git identity of the repo in place
│   ├── e2e-nested-session.sh       Opt-in (`E2E=1`) hook checks in real nested `claude -p` sessions; `E2E_OLD_REF=<ref>` replays them against older hooks
│   ├── measure-memory-injection.sh  Memory injection overhead measurement
│   ├── measure-userpromptsubmit.sh  Hook-latency measurement (run when chain grows)
│   ├── run-all.sh                  Runs the full test suite
│   ├── SMOKE-TESTS.md              Manual smoke test scenarios
│   ├── test-bash-guard.sh          bash-guard.sh deny/allow/ask assertions (destructive cmds, secrets path blocking, env-dump blocking, prefer-jq, recursive-rm scoping, uv add/pip install notice)
│   ├── test-block-sensitive-writes.sh   block-sensitive-writes.sh deny/allow assertions
│   ├── test-bootstrap-doctor.sh    bootstrap-doctor.sh: an ok line or a MISSING line for each check, and the exit code
│   ├── test-branching.sh           Trivial-edit criteria and branch-reuse logic
│   ├── test-brew-sync.sh           brew-sync.sh dump and refresh only add Brewfile entries; shared.bash calls refresh
│   ├── test-commit-msg-lint.sh     commit-msg-lint.sh rules R0 to R11, exempt subjects, --types, and real commits through the hook
│   ├── test-compact-hooks.sh       PreCompact handoff-writing end-to-end test
│   ├── test-context-watch.sh       context-watch.sh 60% directive emit/one-shot assertions
│   ├── test-cost-guard.sh          cost-guard.sh tiering, hard-block, and limit-override assertions
│   ├── test-em-dash-guard.sh       Verifies block-em-dash.sh hook fires on U+2014 payloads
│   ├── test-install-bashrc.sh      install.sh symlink and bashrc wiring assertions
│   ├── test-install-fresh-home.sh  The real install.sh run twice on an empty HOME: no abort, no change the second time; the doctor agrees
│   ├── test-install-hostkeys.sh    install.sh --hostkeys-only with a stub gh: writes only when the fingerprints match
│   ├── test-lib-cov.sh             tests/lib/cov.sh counts executed lines on a known fixture
│   ├── test-lib-fresh-home.sh      tests/lib/fresh-home.sh builds a throwaway HOME and never touches the real one
│   ├── test-maintenance-check.sh   maintenance-check.sh on a HOME with no plans or projects folder
│   ├── test-memory-doctor-guardrails.sh  Proves memory-doctor.sh checks I-M fail-then-pass
│   ├── test-memory-hooks.sh        Memory seed hook and marker-pruning assertions
│   ├── test-migrate-memory-guard.sh  migrate-memory.sh dry-run-default and template-stub-refusal assertions
│   ├── test-no-stale-refs.sh       No tracked file names a removed thing; README.md and AGENTS.md name only tracked repo paths
│   ├── test-post-edit-lint-dispatch.sh  PostToolUse lint hook dispatch tests
│   ├── test-r-lint-staged.sh       r-lint-staged.sh assertions
│   ├── test-repo-hook-install.sh   install-repo-hooks.sh and ensure-repo-hooks.sh: three hooks in a plain repo, a linked worktree, and a core.hooksPath repo
│   ├── test-rules-integrity.sh     rules-doctor.sh passes a green tree and names each targeted check when every drift is applied at once
│   ├── test-session-start-context.sh  session-start-context.sh additionalContext delivery assertions
│   ├── test-staged-lint-dispatch.sh     Pre-commit staged-lint hook dispatch tests
│   ├── test-statusline-context-bridge.sh  statusline pct-file write and 60% marker assertions
│   └── test-stop-hook-git-check.sh  stop-hook-git-check.sh exit-code assertions
```

---

## Setup on a new machine

Do the steps in this order. Steps 1 to 6 prepare the machine. Steps 7 and 8 apply to each project.

### 1. Clone

```bash
git clone git@github.com:datasci-iopsy/anaiis-dotfiles.git ~/anaiis-dotfiles
```

### 2. Run the installer

```bash
bash ~/anaiis-dotfiles/install.sh
```

The installer runs these phases in order:

1. It links `~/anaiis-dotfiles` to the repo when the repo lives elsewhere. Then it links `claude/settings.json`, `claude/keybindings.json`, and the `claude/` folders (`rules`, `commands`, `skills`, `agents`, `hooks`, `scripts`, `memory`) into `~/.claude/`.
2. It wires the shell config.
3. It adds the GitHub host keys.
4. It links `claude-cleanup` into `~/.local/bin/` and `.lintr` to `~/.lintr`. It prints the Homebrew commands and does not run them.

Each output line starts with a status word. `ok` means nothing changed. `link` and `add` mean the installer wrote something. `unlink` means it removed the old `CLAUDE.md` link. `note` and `skip` name a step that it left alone, with the reason. `SKIP` means a real file blocks a link: back it up and remove it first. A second run prints no `link` and no `add` line.

The installer removes the old `CLAUDE.md` link from `~/.claude/` when the link points into this repo. It leaves a real file or any other link in place and prints a `note`. Claude Code still reads such a file.

**Shell config.** The installer creates `~/.bashrc` when the file is absent. It leaves the PATH line as it is when the file holds exactly one canonical PATH line. Otherwise it strips every older form of the line and appends the canonical one. It adds a `source` line for `shared.bash`, before the `~/.bashrc.local` line when the file has one. It creates `~/.bash_profile` with one line that sources `~/.bashrc` only when none of `~/.bash_profile`, `~/.bash_login`, and `~/.profile` exists. If `~/.bash_login` or `~/.profile` exists, it prints a `note` and creates nothing. It never edits an existing `~/.bash_profile`.

**GitHub host keys.** A plugin clone over SSH fails when `~/.ssh/known_hosts` has no `github.com` key. The installer adds the keys only when all of these hold:

- `gh` is installed, and `gh config get git_protocol` prints `ssh`.
- `known_hosts` has no `github.com` entry.
- The fingerprints of the keys from `gh api meta` equal the fingerprints that the same response lists.

The installer computes the fingerprints of the fetched keys with `ssh-keygen` and requires the two sets to be equal. On any doubt it writes nothing, prints one `skip` line with the reason, and goes on. A doubt is an empty answer, a different fingerprint, a failed tool, or a folder that it cannot write. It creates `~/.ssh` (mode 700) only after the check passes. When it writes, it prints the ED25519 fingerprint. To run only this phase later (for example after `gh auth login`), use `--hostkeys-only`.

Three flags run one part of the installer:

- `--symlinks-only`: phase 1 only, with the removal of the old `CLAUDE.md` link. CI uses it to build the `~/.claude` tree that the test suite expects.
- `--bashrc-only`: the shell config only.
- `--hostkeys-only`: the host keys only.

### 3. Open a new terminal

The shell reads the new lines only when it starts. Open a new terminal. The PATH line puts `web-verify` on your PATH. For zsh or fish, the installer does not edit your config. Add the line by hand to the file that your shell reads:

```bash
export PATH="$HOME/anaiis-dotfiles/bin:$PATH"
```

The old CodeRabbit wrapper for the `claude` command was removed on 2026-05-11. `which claude` now resolves to the real Homebrew-installed CLI.

### 4. Start Claude Code and reload the plugins

**Warning.** Install Homebrew bash before the first start. `settings.json` pins `/opt/homebrew/bin/bash`, and every `PreToolUse` guard blocks when that file is absent. Claude Code then denies each Read, Write, Edit, and Bash call, including the call that would install bash. Run `brew install bash` in a terminal outside Claude Code. The same command recovers a machine that is locked out. To install every Brewfile entry, run `bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh install`.

Start Claude Code once in a trusted folder. Then run `/reload-plugins` inside Claude Code. The plugins and their marketplaces come from `claude/settings.json` (`enabledPlugins`, `extraKnownMarketplaces`). If a plugin does not load, read the Errors tab of `/plugin`. A GitHub clone over SSH needs the host key from step 2.

### 5. Run the doctor

```bash
bash ~/.claude/scripts/bootstrap-doctor.sh
```

The doctor only reads. It prints `ok <what>` for each passing check and `MISSING <what>: <fix>` for each gap. The last line is `doctor: <n> missing`. The doctor exits 1 when `n` is above 0. A check that does not apply prints `ok` with the reason, for example `ok github.com host key (not needed: gh not found)`. The doctor runs seven checks:

| # | Check | The fix that the MISSING line names |
|---|---|---|
| 1 | `~/.bashrc` exists and holds the PATH line and the `shared.bash` source line | `bash ~/anaiis-dotfiles/install.sh --bashrc-only` |
| 2 | The login shell file (the first of `~/.bash_profile`, `~/.bash_login`, `~/.profile`) mentions `~/.bashrc` | Add the line that the message prints (`install.sh --bashrc-only` when no login file exists) |
| 3 | Each of nine `~/.claude` links resolves into `~/anaiis-dotfiles/claude` | `bash ~/anaiis-dotfiles/install.sh --symlinks-only` |
| 4 | Each plugin that `enabledPlugins` sets to `true` has a folder in `~/.claude/plugins/cache/` | Start Claude Code once, run `/reload-plugins`, read the Errors tab of `/plugin` |
| 5 | When `gh` uses the SSH protocol, `~/.ssh/known_hosts` holds a `github.com` key | `bash ~/anaiis-dotfiles/install.sh --hostkeys-only` |
| 6 | When `claude` is on PATH, its version is at least 2.1.295 (the first version that supports `onFailure` for `PreToolUse` guards) | Update Claude Code |
| 7 | `settings.json` pins `env.CLAUDE_CODE_SHELL` to an executable bash whose major version is in `APPROVED_BASH_MAJORS`, and every command in it starts with `${CLAUDE_CODE_SHELL:-bash}` | Set the pin, install an approved bash, or approve the major (see "Bash baseline") |

The nine links in check 3 are `settings.json`, `keybindings.json`, `rules`, `commands`, `skills`, `agents`, `hooks`, `scripts`, and `memory`. Check 4 needs `jq`. Without `jq` the doctor prints `MISSING jq (needed to read the plugin list): brew install jq`.

Do not use `claude plugin list` as the check. The doctor reads the plugin cache folders (check 4). A plugin shows MISSING until Claude Code has fetched it, so run the doctor after step 4.

### 6. Set the git identity

The dotfiles set no git identity. Set it once in the global git config of each machine:

```bash
git config --global user.name "<name>"
git config --global user.email "<id>+<login>@users.noreply.github.com"
```

`<id>` is the numeric id of your GitHub account, and `<login>` is its login. Claude Code sessions use the same git config: `claude/settings.json` sets no `GIT_AUTHOR_*` or `GIT_COMMITTER_*` variable, and a value there would override the git config of every repo. To use another identity in one repo, run the same commands there without `--global`. In this repo, a pre-commit check rejects a commit whose email is not a GitHub noreply address. The `attribution` block of `claude/settings.json` controls only the `Co-Authored-By` trailer, not the author.

### 7. Per-project memory bootstrap

Run once from each project root you'll use Claude in:

```bash
cd /path/to/project
bash ~/.claude/scripts/seed-memory.sh
```

In Claude Code, `/seed-project` runs the same script. Then edit `~/.claude/projects/<encoded-path>/memory/project_current_phase.md`.

### 8. Repo hooks: pre-commit lint, pre-push tests, commit-msg lint

Three dispatcher hooks go into every repo:

- `pre-commit` runs the staged-file linters (R, Python, Shell, JSON, SQL) so commits stay fast.
- `pre-push` runs the repo's `tests/run-all.sh`, if it has one. The full suite then gates code that leaves the machine, not every commit (`SKIP_TESTS=1 git push` to bypass). A push with nothing to send, or one that only deletes remote branches, skips the suite and returns git's own `Everything up-to-date`.
- `commit-msg` checks the message against the commit rubric in `rules/git.md` (section "Commit rubric"). It checks only in a repo that has a `.conventional-commits` file at its root. This repo tracks that file. Other repos accept any message. The hook rejects a message that breaks a rule. It prints one `commit-msg-lint: R<n> <reason>` line for each rule (`SKIP_COMMIT_LINT=1 git commit` to bypass).

To check a draft before you commit, run `bash ~/.claude/scripts/commit-msg-lint.sh <message-file>`. The flag `--types` prints the allowed types.

In Claude Code, `ensure-repo-hooks.sh` installs all three on the first prompt in any repo. It also adds the missing hooks to a repo that has only some of them. For repos you commit to outside Claude (direct CLI commits, CI), run once from the project root:

```bash
bash ~/.claude/scripts/install-repo-hooks.sh
```

The installer asks git where the hooks folder is (`git rev-parse --git-path hooks`). In a linked worktree that is the one folder that all worktrees share. When `core.hooksPath` is set, the installer writes the three dispatchers there and not into `.git/hooks`.

---

## Memory system

Memory, compaction, and session history are three separate layers:

- **Memory files** (`claude/memory/` global tier, `~/.claude/projects/<key>/memory/` project tier): stable facts explicitly saved; persist across sessions; delivered to the model by `session-start-context.sh` (a SessionStart hook, matchers `startup|resume|clear|compact`) via `hookSpecificOutput.additionalContext`. This is the channel that actually reaches Claude, not `systemMessage`, which is display-only and never delivered to the model, a bug that went undetected for months before the 2026-07-15 memory-system review.
- **Compaction**: triggered manually (`/compact`) or automatically by the harness at 60% context (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60` in `shared.bash`; policy in `rules/session.md`). The compactor summarizes the conversation itself and does not read memory files to decide what to keep.
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

CodeRabbit reviews are driven entirely from the terminal via the `anaiis-review:rabbit-sweep` skill (marketplace plugin `anaiis-review`). No VS Code paste, no wrapper script.

```bash
# Local mode, from any non-main branch after committing your work:
/anaiis-review:rabbit-sweep
# PR mode, triage the CodeRabbit bot comments on an open PR:
/anaiis-review:rabbit-sweep --pr 42
# Optional local-mode overrides:
/anaiis-review:rabbit-sweep --base feat/my-branch --type committed
```

Both modes share one loop: triage by severity (skip 1-2 with a logged rationale, fix 3-5), fix with the plugin's `code-surgeon` agent, verify in two stages (tests, then intent), commit, and push committed fixes behind branch guards. Hard limits, the mode router, and the phase files are documented in the skill's `SKILL.md`. Its companion `anaiis-review:pr-af` runs the AgentField pr-af engine on a PR and cross-references its findings against the CodeRabbit threads.

### After triage

```
/anaiis-git-ops:rebase      consolidate CR fix commits into logical groups
/anaiis-git-ops:changelog   generate PR description from clean history
/anaiis-git-ops:pr          open the PR
```

The skill never chains into these on its own; each is a separate explicit invocation.

### Audit trail

Each run writes a JSONL ledger under `~/.claude/rabbit-sweep/runs/` with every triage decision, verification result, and commit event.

---

## Skills, commands, rules, agents

### Skills (custom, lazy-loaded)

All custom skills are served by the `datasci-iopsy/anaiis-plugins` marketplace, enabled per plugin in `claude/settings.json`. None of them has a copy in this repo. Invoke as `/<plugin>:<skill>`:

| Plugin | Skills |
|---|---|
| `anaiis-review` | `anaiis-docaudit`, `anaiis-peerreview`, `anaiis-skillreview`, `pr-af`, `rabbit-sweep` |
| `anaiis-git-ops` | `changelog`, `pr`, `rebase` |
| `anaiis-data` | `anaiis-dashboard`, `anaiis-duckdb`, `anaiis-termchart`, `anaiis-webverify`, `graphify` |
| `anaiis-writing` | `anaiis-copyedit`, `anaiis-litreview` |
| `anaiis-meta` | `anaiis-agents` |

`dbt-*` skills are served via the `dbt-labs/dbt-agent-skills` marketplace (registered in `claude/settings.json` under `extraKnownMarketplaces`). They require no local files and do not appear in this repo.

`claude/skills/` is the mount point for local skills (Anthropic-synced skills under `synced/`, AgentField skill symlinks); both are gitignored. See `claude/skills/README.md` for the conventions.

**ponytail** (`DietrichGebert/ponytail`, declared in `claude/settings.json` under `extraKnownMarketplaces` and `enabledPlugins`) is the build-behavior layer. Its SessionStart hook injects a lazy-senior-dev ruleset into every session and subagent: reuse what exists, prefer the standard library and platform features, write the smallest complete change, never cut validation at trust boundaries. It replaced the four Karpathy-derived imperatives that used to open `rules/behavioral.md` (2026-10-26). `PONYTAIL_DEFAULT_MODE` in `bash/shared.bash` pins the level to `full`; `/ponytail lite|full|ultra|off` changes it for one session. A new machine picks the plugin up on the first session start after `install.sh`. The hook path is the only one that works: a copy of the skill file in a skills folder measured zero activations in JetBrains' test, so never hand-copy it.

`evals/ponytail/` measures it with Claude Code's own `claude plugin eval` (with-plugin versus no-plugin arms). `bash evals/ponytail/build-rules-prompt.sh trimmed` generates the case files with the current rules as the system prompt; `bash evals/ponytail/run.sh --tag ab --runs 3 --scaffold --keep-temp --allow-tools Write Edit --max-cost-usd 8 --json out.json` runs the paid suite; `bash evals/ponytail/loc.sh out.json` adds lines-of-code per run from the kept workspaces. Results and the plugin copy under test are gitignored; the write-up lives in `reports/`.

### Commands

| Command | What it does |
|---|---|
| `/seed-project` | Init per-project memory files from templates |
| `/install-hooks` | Install the pre-commit lint, pre-push test, and commit-msg lint dispatchers in a repo |

### Rules

Claude Code loads every file in `~/.claude/rules/` by itself, so no index file exists. `rules-doctor.sh` checks that each rule file has a `description:` line and that each `rules/<name>.md` named in a rule file exists.

| File | Covers |
|---|---|
| `rules/context.md` | Project context, build scope, rule precedence, author identity, machine-local rule files, memory tiers, Postman CLI note |
| `rules/behavioral.md` | The 8 imperatives: authorization before action, model judgment scope, surface conflicts, fail loud, plan and checkpoint, hook output is not user input, investigate is read-only, check before you ask or hedge. Build scope (how much code to write) is the ponytail plugin's, see Skills |
| `rules/environment.md` | macOS, Bash, direnv, uv, worktree safety, rm -rf splitting, configuration homes (shell variable, `env` block, or settings key) |
| `rules/tools.md` | gh, jq, gcloud, make, structured CLI output flags |
| `rules/code-style.md` | ASD-STE100 default writing register, shell formatting, no emojis, convention conformance |
| `rules/git.md` | Typed branches (`claude-<type>/<ticket>-<desc>`), trivial-edit criteria, the commit rubric (section "Commit rubric": types, subject grammar, footers, breaking changes, reverts, opt-in lint), PR title format, push, criteria for a worktree or a branch in place |
| `rules/r-conventions.md` | Vectorization, lapply/vapply, lintr style |
| `rules/python.md` | uv, direnv, ruff |
| `rules/session.md` | Token efficiency, subagent limits, context thresholds, output preferences |
| `rules/work-tracking.md` | Slug layout for `spec/` and `tasks/`, file names per kind, stream files, `_archive/`, skill default paths, todo item format |
| `rules/duckdb.md` | DuckDB query discipline (purpose-based patterns) |
| `rules/citations.md` | Citation integrity (corpus-only sources, no fabrication) |
| `rules/testing.md` | Test-intent discipline: tests must encode why, not just what; fail-to-fail check |
| `rules/dashboards.md` | Dashboard data provenance, manifest discipline, narrative-data alignment, audience language |

### Agents

`claude/agents/` is intentionally empty. Skill-specific agents (`code-surgeon`, `coderabbit-triage`, `intent-verifier`, `rebase-planner`) belong to the plugin that defines their inputs and outputs and live in the plugin cache. See `claude/agents/README.md` for when a cross-skill agent would belong here.

---

## Hooks

Configured in `claude/settings.json`. Scripts in `claude/hooks/`.

| Event | Matcher | Script | Behavior |
|---|---|---|---|
| `UserPromptSubmit` |, | `maintenance-check.sh` | Weekly plan-file check; monthly session-storage check; weekly repo-hooks audit (pre-commit and commit-msg dispatchers) |
| `UserPromptSubmit` |, | `ensure-repo-hooks.sh` | Silently installs the pre-commit, pre-push, and commit-msg dispatchers in the current repo if any is missing. Works in a linked worktree |
| `UserPromptSubmit` |, | `list-merged-claude-branches.sh` | Advisory: lists merged Claude branches (`claude-<type>/*`, and legacy `claude/*`) and shows the delete command |
| `SessionStart` | `startup\|resume\|clear\|compact` | `session-start-context.sh` | Delivers the global memory tier via `additionalContext` (startup/clear/compact); restores the newest pre-compact handoff (compact); advises `/seed-project` when the current project has no memory dir; delivery-gated monthly staleness advisory |
| `PostToolUse` | `Edit\|Write` | `post-edit-lint.sh` | `.py` ruff; `.sh` shfmt (auto-fix) + shellcheck; `.sql` sqlfmt; `.R` lintr; `.json` jq --indent 4 |
| `PostToolUse` | `*` | `context-watch.sh` | At >=55% context (read from the statusline's per-session pct file), five points ahead of the 60% harness backstop, emits a one-shot directive to checkpoint and continue |
| `PreToolUse` | `Write\|Edit\|MultiEdit\|NotebookEdit`, `ExitPlanMode` | `block-em-dash.sh` | Rejects any payload containing U+2014 (em dash); enforces no-em-dash code style rule |
| `PreToolUse` | `Write\|Edit\|MultiEdit\|NotebookEdit` | `block-edit-on-main.sh` | Blocks all edits when the current branch is `main` or `master` |
| `PreToolUse` | `Read\|Write\|Edit` | `block-sensitive-writes.sh` | Read: block `*.env`/`*.env.*`; Write/Edit: block `*.lock`, `*.env`/`*.env.*`, `*credentials*`, `*secret*`, `*.pem`, `*.key`; both allow `*.env.example`/`*.env.template` |
| `PreToolUse` | `Bash` | `bash-guard.sh` | Single guard: blocks destructive commands (`bq rm`, `gcloud delete*`, `uv cache clean`/`pip uninstall`), reads/writes to `.env`, credential paths (`.key`, `.pem`, `~/.aws/**`, `~/.config/gcloud/**`), shell rc files, and environment dumps (`printenv`/`echo $SECRET`); the block message names the matched token, and code idioms (`process.env.NAME`, `import.meta.env`) and the bare word `credentials` are not treated as paths; blocks Python for pure JSON parsing (jq's job); emits a non-blocking `[deps]` notice for `uv add`/`uv pip install`; recursive `rm` gets a scoped `allow`/`ask` decision (safe-list paths silently allowed, everything else asks, catastrophic operands like bare `/` or `~` hard-deny) instead of settings.json's old blanket deny |
| `PreToolUse` | `Agent\|WebFetch` | `cost-guard.sh` | Cost tiering MEDIUM/HIGH/VERY HIGH; hard-blocks (exit 2) general-purpose agents above per-session cap (default 5, override via `COST_GUARD_GP_LIMIT`); blocks logged to `~/.claude/logs/cost-guard-blocks.log` |
| `Stop` |, | `stop-hook-git-check.sh` | Exits 2 (continues agent loop) on uncommitted changes, untracked files, or unpushed commits; exits 0 when clean |
| `PreCompact` | `*` | `pre-compact.sh` | Writes a structured handoff to project memory |
| `StatusLine` | n/a | `statusline-command.sh` (in `scripts/`) | Custom status line display; also bridges the exact context percentage to `context-watch.sh` via a per-session `/tmp` file |
| (in project repos) | n/a | `repo-pre-commit.sh` | Pre-commit dispatcher: staged-file linters only (R, Python, Shell, JSON, SQL); installed into repos by `install-repo-hooks.sh`; not a Claude Code hook |
| (in project repos) | n/a | `repo-pre-push.sh` | Pre-push dispatcher: runs the repo's `tests/run-all.sh` when present and the push sends commits (skipped for no-op pushes and deletions; `SKIP_TESTS=1 git push` to bypass); installed alongside pre-commit; not a Claude Code hook |
| (in project repos) | n/a | `repo-commit-msg.sh` | Commit-msg dispatcher: runs `commit-msg-lint.sh` only in a repo with a `.conventional-commits` file at its root (the opt-in marker); skipped when the marker or the validator is absent or `SKIP_COMMIT_LINT=1`; installed alongside the other two; not a Claude Code hook |

Hook latency on this machine (measured 2026-07-15, 3-hook chain after the memory-delivery hooks moved to SessionStart): aggregate UserPromptSubmit chain median = **81 ms** (under 100 ms target). Re-measure with `bash tests/measure-userpromptsubmit.sh` if the chain grows.

---

## Shell / R / SQL / Python style enforcement

| Language | Edit-time | Commit-time | Bypass |
|---|---|---|---|
| **Shell** | `post-edit-lint.sh` auto-applies `shfmt -w -i 0 -bn -ci` | `shfmt-lint-staged.sh` blocks | `SKIP_SHFMT=1 git commit …` |
| **R** | `post-edit-lint.sh` runs `lintr` and reports | `r-lint-staged.sh` blocks if violations | `SKIP_R_LINT=1 git commit …` |
| **SQL** | `post-edit-lint.sh` auto-applies `sqlfmt` (the file's own project `[tool.sqlfmt]` config, else line_length=120; jinja-aware) | `sqlfmt-lint-staged.sh` blocks | `SKIP_SQLFMT=1 git commit …` |
| **Python** | `post-edit-lint.sh` runs `ruff check --fix` (safe fixes applied; unused imports, F401, are reported and kept) + `ruff format` (auto-applied) | `ruff-lint-staged.sh` blocks | `SKIP_RUFF=1 git commit …` |
| **JSON** | `post-edit-lint.sh` enforces `jq --indent 4` | `json-lint-staged.sh` checks indent | n/a |

`~/.lintr` is symlinked from this repo (`.lintr`). Per-project `.lintr` overrides are honored, lintr walks up from the project root.

---

## Tests and CI

`tests/run-all.sh` runs every `tests/test-*.sh` suite, prints per-suite wall time, and exits non-zero if any suite fails. The suites are hermetic: they resolve hooks and scripts through the repo, build any home tree they need under `mktemp -d`, and never read or write the real `~/.claude`, so results match between a loaded dev machine and a clean runner.

The `tests` GitHub Actions check (`.github/workflows/tests.yml`) runs the same command on `macos-latest` for every pull request and for pushes to `main`. The runner installs Homebrew `bash`, `shfmt`, and `shellcheck` only if the image lacks them, then runs `install.sh --symlinks-only` to build the `~/.claude` symlink tree the hooks expect. macOS on purpose: the hooks use BSD-only forms (`date -j`, `stat -f`) and only ever run on macOS.

A last CI step runs seven bootstrap suites with `/bin/bash`, which is bash 3.2 on macOS, and stops at the first failure. A fresh Mac starts on bash 3.2, so the new scripts must run there. The seven suites are `test-brew-sync`, `test-maintenance-check`, `test-install-bashrc`, `test-install-hostkeys`, `test-bootstrap-doctor`, `test-no-stale-refs`, and `test-install-fresh-home`.

```bash
bash tests/run-all.sh                       # full suite, the same command CI runs
bash tests/test-bash-guard.sh               # one suite while iterating
/bin/bash tests/test-no-stale-refs.sh       # one suite on bash 3.2
COV=1 bash tests/test-brew-sync.sh          # adds approximate line coverage (bash 4.1 or later)
```

The suites for the bootstrap and commit-lint scripts accept `COV=1`. The helper is `tests/lib/cov.sh`. On bash 3.2 it prints one `SKIP` line, and the suite still passes. The doc check in `tests/test-no-stale-refs.sh` fails when this README or `AGENTS.md` names a path that git does not track. Here a path is a backticked name that starts with `claude/`, `tests/`, `bash/`, or `bin/`.

---

## Bash baseline

The harness runs on one approved Homebrew bash major. The line `APPROVED_BASH_MAJORS="5"` in `claude/scripts/bootstrap-doctor.sh` lists the approved majors. A bash 4 fails the checks. A bash 6 fails them until you add 6 to that line.

- **The pin.** `env.CLAUDE_CODE_SHELL` in `claude/settings.json` is `/opt/homebrew/bin/bash`. It selects the shell of the Bash tool. Without it, Claude Code reads `$SHELL`, and VS Code hands it a stale `/bin/bash` (bash 3.2). With no `$SHELL` at all, Claude Code picks zsh.
- **The prefix.** Every hook and status line command in `settings.json` starts with `${CLAUDE_CODE_SHELL:-bash}`. The hooks then run on the pinned bash even when PATH has no Homebrew.
- **Two tiers.** `install.sh`, `bootstrap-doctor.sh`, and `bash/shared.bash` run on bash 3.2, because they run before Homebrew bash exists. Everything else runs on the approved major.
- **Checks.** Doctor check 7, `tests/test-bash-baseline.sh` (part of `run-all.sh`), and the opt-in `E2E=1 bash tests/e2e-bash-shell.sh`. The e2e suite starts real sessions in three launch environments and reads the bash major of the Bash tool and of a hook. Each environment also runs without the pin, and that control must show the defect.
- **Another Homebrew prefix.** The pin is the Apple Silicon path. A machine with another prefix fails check 7, and the message names the line to change.

## Claude aliases

`ANTHROPIC_MODEL=opusplan` is the default for a plain `claude`. The aliases start one model with one effort level. Each passes `--model`, which outranks `ANTHROPIC_MODEL`, and `--permission-mode bypassPermissions`.

| Alias | Model | Effort |
|---|---|---|
| `claude-fast` | `opusplan` | the exported level |
| `claude-turbo` | `opusplan` | xhigh |
| `claude-fable`, `claude-fable-turbo`, `claude-fable-max` | Fable 5.1 | high, xhigh, max |
| `claude-opus`, `claude-opus-turbo`, `claude-opus-max` | Opus 5.5 | high, xhigh, max |

`tests/test-shared-bash-aliases.sh` ties the model id of each alias to its `ANTHROPIC_DEFAULT_*_MODEL` export, under bash 3.2 and bash 5. While `CLAUDE_CODE_EFFORT_LEVEL` is exported, `/effort` and `--effort` have no effect, so use an alias to change the effort for one launch.

---

## Worktrees

Choose a worktree or a branch in place by the criteria in `rules/git.md`, section "Worktree or branch in place": live config, foreign changes in the main checkout, parallel streams, or a request. In this repo a worktree is the default, because the `~/.claude/*` links point at the main checkout.

- **Where.** Worktrees live under `tmp/worktrees/<id>` inside the main checkout. Git ignores `tmp/`, `tasks/`, and `spec/`. Those folders exist only in the main checkout, so edit them there by absolute path.
- **Live config.** The `~/.claude/*` links point at `~/anaiis-dotfiles/claude/`, which is the main checkout. `install.sh` resolves the main worktree as the canonical path, even when you run it from a worktree. Hook commands in `claude/settings.json` call `$HOME/.claude/hooks/...`, so a hook runs the code of the main checkout. A change in a worktree reaches `~/.claude/` only after it merges.
- **Tests.** Run `bash tests/run-all.sh` from the worktree root. A script that reads `~/.claude` needs a throwaway HOME. `tests/lib/fresh-home.sh` builds one whose `~/.claude` links point at the worktree under test.
- **Installer.** Test `install.sh` only in a throwaway HOME. Even there, its links point at the main checkout and not at the worktree.
- **Git hooks.** All worktrees share one hooks folder. Test hook installers only in a throwaway repo. `install-repo-hooks.sh` and `ensure-repo-hooks.sh` work in a linked worktree.
- **Memory.** The project key comes from the working directory, so each worktree has its own project memory tier. Memory saved in one worktree does not appear in another.
- **Stop hook.** `stop-hook-git-check.sh` reports only the git state of the current folder. Check another worktree with `git -C <path> status --short`.
- **Parallel work.** Two worktrees that edit the same file create a merge risk. Give each worktree its own set of files.

---

## Usage report

Run at any time to see session counts, token totals (comma-formatted), agent spawn distribution, and cost-guard block counts. Add `--json` for raw integers suitable for `jq` pipelines or Claude audits:

```bash
bash ~/.claude/scripts/usage-report.sh --since 2026-05-01
bash ~/.claude/scripts/usage-report.sh --since 2026-04-01 --until 2026-04-30 --json
```

---

## Homebrew packages

A `Brewfile` at the repo root tracks all formulae, casks, and taps. Three commands cover the full lifecycle:

```bash
# New machine: install everything in the Brewfile
bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh install

# Check for drift (packages installed but not in Brewfile, or missing)
bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh check

# After installing something new: add it to the Brewfile and commit
bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh dump
git add Brewfile && git commit -m "build(deps): add <formula> to Brewfile"
```

`install.sh` prints the `install` command as a reminder but does not run it automatically (bundle install can take several minutes on a fresh machine and may prompt for sudo).

**The Brewfile refresh is additive only.** `dump` and the daily refresh add entries and never remove or rewrite a line. An entry is new when its type and quoted name (for example `brew "pup"`) are not in the file yet. When an existing line has the same key, the existing line stays, so `brew "pup", trusted: true` is not duplicated. Several profiles share the package list, and a profile may lack a package that another profile installed. To remove an entry, edit `Brewfile` by hand.

`shared.bash` runs `brew-sync.sh refresh` in the background at each shell start. The `refresh` verb works at most once per 24 hours. It stays silent unless it added entries, and then it prints a one-line notice. Commit the changed file from a dotfiles session.

### Shared prefix across macOS profiles

Several admin profiles on one Mac share `/opt/homebrew`. Homebrew creates files with the mode of the invoking profile, so a keg installed by one profile blocks upgrades from the others. One command fixes this for existing and future files:

```bash
sudo bash ~/anaiis-dotfiles/claude/scripts/brew-share.sh
```

It adds two inheritable ACL entries for group `admin` to the prefix, one for directories and one for files. Paths any admin profile creates later inherit them. Homebrew gains no rights and still runs as the invoking profile. The file entry omits `execute` on purpose: a file with an ACL `execute` grant reports as executable, so the cask installer skips its own `chmod +x` and the binary lands without an x bit. The script is idempotent; re-run it to repair files created outside the ACL or to migrate the older single-entry layout.

---

## Per-machine prerequisites

`install.sh` links the config and wires the shell. It does not install packages. The CLI tools the hooks need (`gh`, `jq`, `shellcheck`, `shfmt`, `ruff`, `uv`, `shandy-sqlfmt`) are in the Brewfile; install them with:

```bash
bash ~/anaiis-dotfiles/claude/scripts/brew-sync.sh install
```

The `graphify` skill is served by the `anaiis-data` marketplace plugin. Nothing to install per machine.

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
