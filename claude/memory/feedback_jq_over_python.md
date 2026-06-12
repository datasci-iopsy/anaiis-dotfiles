---
name: jq-over-python
description: jq is the correct tool for JSON parsing in bash; Python inline scripts are slower, verbose, and require approvals
metadata:
  type: feedback
---

Use `jq` for all JSON parsing in bash. The global CLAUDE.md already states this. Do not write `python3 -c "import json..."` inline scripts to parse JSON -- that violates the tool preference rule and generates approval prompts for non-trivial scripts.

**Why:** `jq` is purpose-built, streaming, handles malformed input more gracefully than bare `json.loads`, and is already in the allowlist (`Bash(jq:*)`). Python inline scripts for JSON are verbose, harder to read, and long enough to trigger approval review even though `Bash(python3:*)` is allowed.

**How to apply:**
- JSONL extraction: use `jq -r 'select(...) | ...' file.jsonl`
- JSON pretty-print: `jq '.' file.json`
- Filtering/transforming API output: `command | jq '.field'`
- Only fall back to Python for JSON if the transform requires control flow that jq cannot express (loops with state, custom aggregations)

The approval friction and verbosity both disappear when jq is used correctly.
