#!/usr/bin/env bash
# extract-behavioral-rules.sh, emit each numbered behavioral imperative from
# rules/behavioral.md as one line, stripped of the Markdown heading prefix.
#
# Output: one line per imperative, e.g. "1. Don't assume..."
# Exit 1 and print to stderr if the file is missing or no headings are found.

set -eu

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"
BEHAV_MD="$REPO_DIR/claude/rules/behavioral.md"

if [ ! -f "$BEHAV_MD" ]; then
	printf 'extract-behavioral-rules: %s not found\n' "$BEHAV_MD" >&2
	exit 1
fi

RULES=$(grep -E '^## [0-9]+\. ' "$BEHAV_MD" | sed 's/^## //' || true)

if [ -z "$RULES" ]; then
	printf 'extract-behavioral-rules: no numbered H2 headings in %s\n' "$BEHAV_MD" >&2
	exit 1
fi

printf '%s\n' "$RULES"
