#!/usr/bin/env bash
# prefer-jq.sh -- block Python when json is the sole import
#
# Triggered by PreToolUse:Bash hook. If a python/python3 command imports json
# and nothing else, it is a pure JSON parsing task that jq handles better.
# Scripts that import additional packages alongside json are allowed through
# (they are doing more than parsing -- data analysis, etc.).
#
# Exit 2 = hard block (unambiguous case -- jq is the right tool).
# Exit 0 = allow.

set -euo pipefail

CMD=$(jq -r '.tool_input.command // empty')

# Only check python/python3 commands
if ! echo "$CMD" | grep -qE '\b(python|python3)\b'; then
	exit 0
fi

# Check if json is imported at all
if ! echo "$CMD" | grep -qE '\bimport\s+json\b'; then
	exit 0
fi

# Two ways another package can be imported alongside json:
#   1. Comma-separated:  import json, pandas ...
#   2. Separate statement: import pandas (on its own line or after semicolon)
#
# If either is present, the script does more than JSON parsing -- allow it.

# Case 1: comma after json on same import line (import json, something)
if echo "$CMD" | grep -qE '\bimport\s+json\s*,'; then
	exit 0
fi

# Case 2: any import statement for something other than json
# Strip import json entirely, then look for remaining import keywords
if echo "$CMD" | sed 's/import[[:space:]]*json//g' | grep -qE '\bimport\s+\w'; then
	exit 0
fi

echo "Prefer jq over Python for JSON parsing -- import json is the only import, this is a pure parsing task. jq is pre-approved, streaming, and faster." >&2
exit 2
