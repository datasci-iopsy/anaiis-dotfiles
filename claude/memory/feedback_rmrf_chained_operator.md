---
name: rmrf-chained-operator-confirmation
description: never chain rm -rf on a disposable cache/build dir with && or other operators in the same Bash call; bash-guard always asks regardless of target safety
metadata:
  type: feedback
---

When clearing a disposable cache/build dir (`.ruff_cache`, `.venv`, `node_modules`,
`dist`, `build`, `.next`, `coverage`, `__pycache__`, etc.) before running a follow-up
command, issue the `rm -rf <path>` as its own standalone Bash call. Never chain it with
`&&`, `;`, a pipe, or a newline onto the next command.

**Why:** `bash-guard.sh` asks for confirmation on any recursive rm alongside a shell
operator/substitution character, unconditionally, before checking the safe-list.
Deliberate, not a bug: an "allow" covers the whole command, so a safe first operand must
never launder a dangerous one riding along. Confirmed by transcript audit (2026-08-07):
every rm-related prompt across several days was this shape. Tracked at
[#15](https://github.com/datasci-iopsy/anaiis-dotfiles/issues/15).

**How to apply:** split a cache-clear-then-something-else command into two Bash calls.
Applies regardless of whether the path is on the safe-list; the operator check fires first.
