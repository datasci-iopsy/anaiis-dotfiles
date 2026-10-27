#!/usr/bin/env bash
# evals/ponytail/build-rules-prompt.sh -- generate each A/B case.yaml with the
# rules text the arm should see.
#
# Eval runs load none of the user's config, so the rules reach the model
# through execution.append_system_prompt. This script fills the __RULES__
# placeholder in every evals/*/case.yaml.tmpl with the concatenated
# code-affecting rules and writes the case.yaml beside it.
#
#   bash evals/ponytail/build-rules-prompt.sh trimmed    # rules from the current branch
#   bash evals/ponytail/build-rules-prompt.sh statusquo  # behavioral.md from STATUSQUO_REV, rest from the branch
#
# Only behavioral.md differs between the two variants, so that is the only
# file read from STATUSQUO_REV. The subset (behavioral, code-style, testing, python,
# r-conventions) is the set of rules that can change what code the agent
# writes; git, session, tools, environment, duckdb, citations and dashboards
# govern hooks and tools that do not exist inside a sandboxed `claude -p` run.

set -eu

VARIANT="${1:-}"
case "$VARIANT" in
	trimmed | statusquo) ;;
	*)
		echo "usage: $0 trimmed|statusquo" >&2
		exit 2
		;;
esac

REPO_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$REPO_DIR"

RULES_DIR="claude/rules"
# Last main commit before ponytail replaced four imperatives. Pinned because
# main:behavioral.md holds the trimmed file once this branch merges.
STATUSQUO_REV="51fb22664342cdb211390f82beae5725f60d123b"
OUT_DIR="evals/ponytail/rules"
mkdir -p "$OUT_DIR"
RULES_FILE="$OUT_DIR/$VARIANT.md"

{
	if [ "$VARIANT" = "statusquo" ]; then
		git show "$STATUSQUO_REV:$RULES_DIR/behavioral.md"
	else
		cat "$RULES_DIR/behavioral.md"
	fi
	for f in code-style testing python r-conventions; do
		printf '\n\n'
		cat "$RULES_DIR/$f.md"
	done
} >"$RULES_FILE"

# Indent the rules by four spaces so they sit inside the YAML block scalar.
# BSD awk rejects newlines in -v strings, so the placeholder line is replaced
# with sed's r command (queue the file, delete the marker).
INDENTED_FILE="$(mktemp)"
trap 'rm -f "$INDENTED_FILE"' EXIT
sed 's/^/    /' "$RULES_FILE" >"$INDENTED_FILE"

for tmpl in evals/ponytail/evals/*/case.yaml.tmpl; do
	out="${tmpl%.tmpl}"
	sed -e '/^__RULES__$/{' -e "r $INDENTED_FILE" -e 'd' -e '}' "$tmpl" >"$out"
	echo "wrote $out ($VARIANT)"
done

printf '%s rules: %s bytes\n' "$VARIANT" "$(wc -c <"$RULES_FILE" | tr -d ' ')"
