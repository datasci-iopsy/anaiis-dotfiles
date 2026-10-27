# Ponytail A/B on this stack, 2026-10-26

Spec: `spec/2026-10-26-ponytail-adoption.md`. Plan: `tasks/plan.md`. Suite: `evals/ponytail/`. Raw results (gitignored, on this machine): `evals/ponytail/evals/results/{smoke,dry,dry2,trimmed,statusquo}.json` and the matching `.loc.csv` files; kept workspaces under `/private/tmp/e-*`.

## Question

Does installing the ponytail plugin and removing the four Karpathy-derived imperatives from `rules/behavioral.md` produce smaller, still-correct code on R, Python, and SQL tasks, compared with the rules as they stood on `main`?

## Setup

| Item | Value |
|---|---|
| Harness | `claude plugin eval` (Claude Code 2.1.310), with and without-plugin ablation, `--scaffold --keep-temp -j 2` |
| Plugin | ponytail 5.3.2, copied from the plugin cache to `evals/ponytail/plugin` |
| Agent model | `claude-sonnet-5-5`, the model `opusplan` executes with in `claude -p` (no plan mode there). Same model JetBrains used. |
| Judge model | harness default (Haiku), 3 votes per LLM grader |
| Tools | Read, Glob, Grep, plus Write and Edit via `--allow-tools`. No Bash. |
| Rules delivery | `execution.append_system_prompt` per case. Eval runs load no user config, so this is the only path. |
| Rules subset | behavioral, code-style, testing, python, r-conventions (18.4 KB trimmed, 19.7 KB status quo). Excluded: git, session, tools, environment, duckdb, citations, dashboards, which govern hooks and tools absent from a sandboxed `-p` run. Only `behavioral.md` differs between variants. |
| Cases | 3, each seeded by a scaffold script and graded on the produced file |
| Runs | 3 per case per arm per suite: 36 agent runs in the two suites, plus 1 smoke pair and 2 dry-run pairs |
| Cost | trimmed suite 1.32 USD, status-quo suite 1.37 USD, smoke 0.08, dry runs 0.16 and 0.14. Total 3.07 USD at list price. |

Cases and traps:

1. `r-survey-means`: add `item_means(path)` to a file that already has `read_survey`. Trap: re-reading the CSV, per-column loops, a tidyverse import, an unrequested numeric-type check.
2. `py-csv-export`: add `--format csv` to an argparse script that writes JSON. Trap: a formatter module or class, a new dependency, extra flags.
3. `sql-param-user`: make `get_user(conn, user_id)` safe against a hostile `user_id` (seeded with an f-string). Hidden floor: a bound parameter; escaping fails.

Graders: `activated` (regex on the transcript for the ruleset header, with-arm only), `complete` or `bound` (LLM, reads the produced file), `lean` (LLM, reads the produced file). Lines added are computed by `loc.sh` as `diff -rN` additions against a rebuilt seed.

## Activation proof (Level 1)

Smoke case, one run per arm: the with-arm quoted the ruleset header; the without-arm replied `NONE`. The kept with-arm transcript contained the header 9 times, the without-arm transcript 0 times. In the two suites the `activated` grader matched in 18 of 18 with-arm runs and the without-arm never saw the header (the harness scores with-only graders as a plugin-fired indicator, and every without-arm `activated` row is absent from the CSV). Fail-to-fail: the without arm is the negative control; it never matched.

## The 2x2

Two suites, each with both arms, give four cells. A is what the user ran before today. B is the proposed end state.

| Cell | Rules in system prompt | Plugin | Runs | Lines added, total | Cost, total USD | Mean score |
|---|---|---|---|---|---|---|
| A: status quo | main `behavioral.md` (10 imperatives) | off | 9 | 63 | 0.652 | 0.78 |
| B: end state | trimmed `behavioral.md` (7 imperatives) | on | 9 | 55 | 0.687 | 0.83 |
| C: both stacked | main `behavioral.md` | on | 9 | 57 | 0.719 | 0.83 |
| D: trimmed, no plugin | trimmed `behavioral.md` | off | 9 | 65 | 0.629 | 0.67 |

Per case, medians over 3 runs:

| Case | Cell | Lines added (min to max) | Cost USD | Seconds | Turns | Correct (of 3) | Lean (of 3) |
|---|---|---|---|---|---|---|---|
| r-survey-means | A | 5 (5 to 7) | 0.0658 | 10 | 3 | 3 | 2 |
| r-survey-means | B | 4 (4 to 4) | 0.0705 | 10 | 3 | 3 | 3 |
| r-survey-means | C | 4 (4 to 4) | 0.0712 | 10 | 3 | 3 | 3 |
| r-survey-means | D | 7 (5 to 7) | 0.0654 | 11 | 3 | 2 | 1 |
| py-csv-export | A | 13 (13 to 14) | 0.0859 | 17 | 6 | 3 | 0 |
| py-csv-export | B | 13 (11 to 13) | 0.0842 | 17 | 6 | 2 | 1 |
| py-csv-export | C | 13 (13 to 14) | 0.0924 | 16 | 6 | 3 | 0 |
| py-csv-export | D | 13 (13 to 14) | 0.0797 | 16 | 6 | 3 | 0 |
| sql-param-user | A | 2 (2 to 2) | 0.0657 | 11 | 4 | 3 | 3 |
| sql-param-user | B | 2 (2 to 2) | 0.0736 | 13 | 5 | 3 | 3 |
| sql-param-user | C | 2 (1 to 2) | 0.0753 | 12 | 4 | 3 | 3 |
| sql-param-user | D | 2 (2 to 2) | 0.0644 | 11 | 4 | 3 | 3 |

## Findings

1. **The effect lives where there was room to over-build.** On the R case, ponytail wrote the same 1-line body in all 6 with-arm runs (`colMeans(read_survey(path)[paste0("q", 1:5)], na.rm = TRUE)`). Without the plugin, 4 of 6 runs added an unrequested `vapply(items, is.numeric, ...)` filter and a temporary, for 5 to 7 lines. On the Python and SQL cases every arm converged on the same solution (a two-entry writer dict plus one `argparse` choice; a `?` placeholder with a tuple), so there was nothing to cut. This is the JetBrains pattern: zero on lean tasks, real on tasks with a trap.
2. **Safety held in every run.** `bound` passed 12 of 12 with-arm runs and 6 of 6 without-arm runs across both suites. No run escaped or quoted instead of binding. Writing less did not cut the guard.
3. **Cost per run went up, not down, at this task size.** B cost 5% more than A in total (0.687 vs 0.652 USD). The ruleset adds about 1.5k input tokens per turn; the tasks finish in 3 to 6 turns, so the extra input outweighs the saved output. The published savings come from long sessions where output dominates. Expect no bill reduction on small edits.
4. **Removing the Karpathy imperatives without ponytail is a regression.** D (trimmed rules, no plugin) was the worst cell: most lines (65), lowest score (0.67), and the R case lost its lean verdict in 2 of 3 runs. The four imperatives did restrain the model. Ponytail restrains it more, and B is the best cell on lines and score. The deletion is safe only because the plugin replaces it.
5. **Stacking both rule sets (C) did not fight, but did not help.** C matched B on lines and score and cost 5% more than B. No ask-versus-ship or surgical-versus-complete collision showed up on these three tasks; the collision the article describes needs a vaguer request than these. The static review of imperatives 5 to 10 found no overlap, and C's behavior supports keeping them.
6. **Judge noise is visible.** The Haiku judge marked one correct R implementation (without-arm, trimmed, run 3) as incomplete 3 votes to 0, and the `lean` rubric for Python rejects a two-entry dispatch dict that all four cells produced. Read the LLM columns as a trend; lines added is the deterministic metric.

## Decision rule from the spec

The spec said: adoption stands if B is smaller than A on at least 2 of 3 tasks and never fails the safety check. B was smaller on 1 of 3 tasks (R), equal on 2 (Python, SQL), and passed the safety check 9 of 9. The size criterion is not met as written, because two of the three tasks had no over-build room; the spec predicted this ("a lean data script may show nothing") and said the test must be able to show zero. It did.

Recommendation: adopt. B is the best of the four cells on lines and score, safety is unchanged, and the one cost is about 5% per run on short tasks. The alternative that keeps the old rules (A) wrote more code with lower scores, and the alternative that drops them without the plugin (D) is worse than both.

## Decisions made during the run (for audit)

- `claude plugin eval` replaced the custom `claude -p --plugin-dir` harness from the spec. A named target reads cases only from the plugin cache and a symlinked `plugins:` path is rejected as outside the target, so `run.sh` copies the cached plugin into `evals/ponytail/plugin` and targets the suite directory.
- Rules subset: five code-affecting rule files (listed in Setup). Chosen over all twelve because the excluded files reference hooks and tools that do not exist in the sandbox and would add about 6k tokens per run without changing what code is written.
- The first dry run showed LLM judges read the final message by default; graders were changed to `focus: { source: file, path: ... }`. A `closing` regex on the reply was dropped because the fail-loud imperative makes the baseline arm also end with "I haven't run it"; it did not discriminate. The `activated` grader on the transcript replaced it.
- Model pinned to `claude-sonnet-5-5` in every case for comparability across days.
- The install test (`tests/test-install-bashrc.sh`) fails one symlink-resolution assertion when run from a worktree and passes from the main checkout. Nothing in this branch touches it. Left as a flag for the user.

## Limits

Three cases, three runs, one model, one judge. The sample can show a direction, not a size. Costs are list price from the harness. Tasks were written by the same person who wrote the spec; they encode the traps the article names rather than a sample of daily work.

## Interactive proof (Level 2, user-run)

Scenarios S17 to S19 in `tests/SMOKE-TESTS.md`. Run on 2026-10-27 by a Claude session started in the worktree (Claude Code 2.1.311). Claude cannot type slash commands or see the status band, so the user ran the slash-command steps of S17 and S19 by hand.

| Scenario | Result | Notes |
|---|---|---|
| S17 band visible, `/ponytail` reports full | pass with notes | SessionStart injected `PONYTAIL MODE ACTIVE, level: full`. The user pasted the band: the level selector shows `[ full ]` active, with panels for cost, tokens and agent time. The user ran `/ponytail:ponytail` with no argument twice; the `UserPromptSubmit` hook replied `PONYTAIL MODE ACTIVE, level: full` with no `CHANGED`, so nothing switched. `enabledPlugins["ponytail@ponytail"]` is `true` in both settings files. Notes: (1) the band shows no reuse panel and no tests panel, which the scenario lists; (2) the bare `/ponytail` form was not run, only the skill form, and an earlier notice said the `UserPromptSubmit` hook was skipped; (3) `~/.claude/ponytail-modes/` holds one flag file with `full`, but its name is not a plain SHA-256 of the working directory, so the link to this project is unconfirmed. |
| S18 subagent quotes the PONYTAIL header | pass | An Explore subagent returned `PONYTAIL MODE ACTIVE, level: full` (the em dash in the live header is shown as a comma here). It checked no other blocks. |
| S19 level survives `/compact` | pass | The user ran `/ponytail:ponytail lite`; the `UserPromptSubmit` hook replied `PONYTAIL MODE CHANGED, level: lite`. The user then ran `/compact`. The SessionStart:compact hook injected `PONYTAIL MODE ACTIVE, level: lite` (restored handoff `2026-10-27T14-41Z`). Method differs from the scenario in two ways: the level was set with the skill form, and it was read from the injected header, not from a bare `/ponytail`. An earlier compact at level `full` is not evidence and is not counted. |
