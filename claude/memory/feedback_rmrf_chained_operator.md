---
name: rmrf-chained-operator-confirmation
description: Never chain rm -rf on a cache/build dir with && or another operator in one Bash call; bash-guard asks regardless of target safety
metadata:
  type: feedback
---

Issue `rm -rf <cache-dir>` as its own Bash call. Never chain it with `&&`, `;`, a pipe, or
a newline onto the next command. `rules/environment.md` holds the runner-command exception.

**Why:** `bash-guard.sh` asks on any recursive rm beside a shell operator before it consults
the safe-list. This is deliberate: an allow covers the whole command, so a safe operand must
never launder a dangerous one. Transcript audit (2026-08-07): every rm prompt had this shape.
Tracked at [#15](https://github.com/datasci-iopsy/anaiis-dotfiles/issues/15).

**How to apply:** split into two Bash calls, even when the path is on the safe-list.
