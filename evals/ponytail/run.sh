#!/usr/bin/env bash
# evals/ponytail/run.sh -- run the ponytail eval suite with the repo's fixed flags.
#
# Wraps `claude plugin eval` so every run uses the same target, case directory,
# and privacy flag (--no-publish keeps the HTML report on this machine). Extra
# arguments pass through, e.g.:
#   bash evals/ponytail/run.sh --case smoke --runs 1 --keep-temp --max-cost-usd 0.50 --json
#   bash evals/ponytail/run.sh --tag ab --runs 3 --scaffold --keep-temp --max-cost-usd 8 --json out.json
#
# First run in a fresh checkout: `claude plugin eval` asks you to trust the
# plugin directory. Answer it once with a small run (--case smoke --runs 1)
# before the paid --json run. Do not add --trust-plugin here; it skips that
# decision for any plugin and is meant for CI.
#
# A named target (ponytail@ponytail) reads cases from the plugin's own cache
# directory, which ships none. So the suite directory is the target and each
# case names the plugin through its `plugins:` field as ../../plugin. The
# harness requires that path to resolve inside the target directory (a symlink
# out to the cache is rejected), so this script copies the newest cached
# version to evals/ponytail/plugin (gitignored) before every run. That keeps
# the case files free of machine paths and pins what was tested.
#
# Results land under evals/ponytail/evals/results/ (gitignored).

set -eu

REPO_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$REPO_DIR"

CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/ponytail/ponytail"
PLUGIN_DIR="${PONYTAIL_PLUGIN_DIR:-$(find "$CACHE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)}"
if [ -z "$PLUGIN_DIR" ] || [ ! -f "${PLUGIN_DIR%/}/.claude-plugin/plugin.json" ]; then
	echo "ponytail plugin not found under $CACHE; install it or set PONYTAIL_PLUGIN_DIR" >&2
	exit 1
fi
for tmpl in evals/ponytail/evals/*/case.yaml.tmpl; do
	if [ ! -f "${tmpl%.tmpl}" ]; then
		echo "missing ${tmpl%.tmpl}; run: bash evals/ponytail/build-rules-prompt.sh trimmed|statusquo" >&2
		exit 1
	fi
done

COPY="$REPO_DIR/evals/ponytail/plugin"
rm -rf "$COPY"
cp -R "${PLUGIN_DIR%/}" "$COPY"
echo "plugin under test: ponytail $(jq -r .version "$COPY/.claude-plugin/plugin.json") from $PLUGIN_DIR" >&2

exec claude plugin eval evals/ponytail \
	--eval-dir evals \
	--no-publish \
	"$@"
