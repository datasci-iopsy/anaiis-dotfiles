---
name: rmrf-chained-operator-confirmation
description: never chain rm -rf on a disposable cache/build dir with && or other operators in the same Bash call; bash-guard always asks on any rm -rf + shell operator combo regardless of target safety
metadata:
  type: feedback
---

When clearing a disposable cache or build directory (`.ruff_cache`, `.venv`, `node_modules`,
`__pycache__`, etc.) before running a follow-up command, issue the `rm -rf <path>` as its
own standalone Bash tool call. Never chain it with `&&`, `;`, a pipe, or a newline onto the
next command in the same call.

**Why:** `bash-guard.sh`'s PreToolUse hook asks for confirmation on any recursive rm that
appears alongside a shell operator/substitution character in the same command string,
unconditionally, before it ever checks whether the target path is on the known-safe list
(`.venv`, `node_modules`, `dist`, `build`, `.next`, `coverage`, `__pycache__`). This is
deliberate (an "allow" decision covers the whole command, so a safe-looking first operand
must never launder a second, dangerous one riding along with it), not a bug. Confirmed via
a full transcript audit (2026-08-07) across one project's prior several days: every rm-related
confirmation prompt was this exact shape. Tracked for a possible hook-side carve-out at
[datasci-iopsy/anaiis-dotfiles#15](https://github.com/datasci-iopsy/anaiis-dotfiles/issues/15).

**How to apply:** Before writing a Bash command that clears a cache/build directory and then
runs something else, split it into two separate Bash tool calls. Applies to any disposable
cache dir, on the hook's safe-list or not, since the operator-chaining check fires first and
doesn't care what the path is.
