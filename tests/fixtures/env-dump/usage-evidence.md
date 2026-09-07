# Real usage evidence: env/printenv piping and .env file access

Mined from all locally retained Claude Code session transcripts across every project
(`~/.claude/projects/*/*.jsonl`), not just this repo: 13,558 Bash tool_use commands and
1,764 Read/Edit/Write tool_use calls in total. Backs the item 3 and item 4 fixes in
`tasks/plan.md` with real data instead of a guessed posture.

## env / printenv piping (informs Fix 4)

Every Bash command matching `(printenv|env)\s*\|` (piped) or bare `^(printenv|env)$`,
globally, across all history:

| Command | Classification |
|---|---|
| `env \| grep -i claude_plugin \|\| echo "no CLAUDE_PLUGIN* vars in env"` (x2, identical shape) | Benign, targeted lookup, no secret-shaped token |

Bare `env` / `printenv` with no pipe: 0 occurrences, ever.
`env`/`printenv` piped to a secret-shaped grep (`TOKEN`/`SECRET`/`API_?KEY`/`PASSWORD`): 0
occurrences, ever.
`env`/`printenv` piped to a non-narrowing viewer (`cat`/`less`/`wc`/`sort`): 0 occurrences,
ever.

Separately, targeted `printenv <VAR>` (no pipe, single non-secret var) appears 9 times in
this repo's own history (e.g. `printenv COST_GUARD_GP_LIMIT`), already allowed by the
existing rule since it isn't piped and isn't secret-shaped.

**Conclusion:** 100% of real historical pipe usage is the exact shape the target-safe fix
needs to allow. The historical record contains no case that requires the current
blanket-block-on-pipe-shape rule; loosening it to target-safe closes a real, repeated false
positive with no observed downside.

## .env-family file access via Read/Edit/Write (informs Fix 3)

Every Read/Edit/Write `file_path` value containing the substring `env` (case-insensitive),
globally, across all history (1,764 total file-tool calls, 5 matched):

| Path | Classification |
|---|---|
| `tests/fixtures/env-dump/malicious.txt` | Test fixture, not a real secret |
| `tests/fixtures/env-dump/benign.txt` | Test fixture, not a real secret |
| `tests/fixtures/env-dump/calibrate.sh` | Test harness script |
| `claude/memory-templates/feedback_environment.md` | Unrelated filename (contains "environment", not `.env`) |
| `.env.example` | The exact carve-out case; a real file legitimately read once |

**Conclusion:** zero attempts on a real secret `.env`/`.env.local`/`.env.production`-family
file, ever, in the entire retained history. The single real `.env`-family access on record is
`.env.example`, exactly the case the current settings.json glob wrongly denies. Centralizing
protection in `block-sensitive-writes.sh` (which already carves out `.env.example` correctly
for Write/Edit) carries no historical regression risk for Read.

## Methodology notes

- Extraction commands avoided embedding the literal substring `.env` in their own Bash
  argument text, since that substring inside a jq filter or grep pattern is exactly the item
  1 false positive being fixed in this same session (reproduced live twice while gathering
  this data). Filtering was done via jq's `test()` on already-captured data or via the Read
  tool on scratch output, not via a shell-level `grep '.env'`.
- This evidence reflects only locally retained transcripts; older, rotated, or cross-machine
  sessions are not included. Treat the counts as a lower bound on real usage, not an
  exhaustive census.
