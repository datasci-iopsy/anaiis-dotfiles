#!/usr/bin/env bash
# tests/test-shared-bash-aliases.sh -- the claude-* aliases in bash/shared.bash match their model exports.
#
# Why this matters: the model id of each family appears in four places in shared.bash: one export
# (ANTHROPIC_DEFAULT_<FAMILY>_MODEL) and three aliases. After a model bump, one forgotten edit starts the
# wrong model for one alias and nothing says so. An alias also beats the exported default only because
# --model outranks ANTHROPIC_MODEL (opusplan), so each alias must carry the flag. Every claude-* alias
# needs a row below: a new alias without a row fails, so nothing goes untested.
#
# shared.bash is sourced by login shells on a fresh Mac (bash 3.2) and on a configured Mac (Homebrew
# bash), so every check runs under /bin/bash and under the bash on PATH.
#
# Method: source shared.bash in a throwaway HOME, print the alias table and the model exports, and compare
# each alias with its row. Fail-to-fail cases break a copy of shared.bash and expect the checks to report it.
#
# Usage: bash tests/test-shared-bash-aliases.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_BASH="$REPO_DIR/bash/shared.bash"

PASS=0
FAIL=0

assert_eq() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' "$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/test-shared-bash-aliases.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/home"

# Each row: alias | model id source | effort | permission mode.
# The source is an export name, or literal:<value> for the opusplan alias, which has no pinned id.
ROWS=(
	"claude-fast|literal:opusplan||bypassPermissions"
	"claude-turbo|literal:opusplan|xhigh|bypassPermissions"
	"claude-fable|ANTHROPIC_DEFAULT_FABLE_MODEL|high|bypassPermissions"
	"claude-fable-turbo|ANTHROPIC_DEFAULT_FABLE_MODEL|xhigh|bypassPermissions"
	"claude-fable-max|ANTHROPIC_DEFAULT_FABLE_MODEL|max|bypassPermissions"
	"claude-opus|ANTHROPIC_DEFAULT_OPUS_MODEL|high|bypassPermissions"
	"claude-opus-turbo|ANTHROPIC_DEFAULT_OPUS_MODEL|xhigh|bypassPermissions"
	"claude-opus-max|ANTHROPIC_DEFAULT_OPUS_MODEL|max|bypassPermissions"
)

# dump <bash> <shared.bash>: source the file in a throwaway HOME and print the alias table and the exports.
dump() {
	# shellcheck disable=SC2016 # the given bash expands these variables, not this shell
	env -i HOME="$TMPD/home" PATH="$PATH" "$1" -c '
		shopt -s expand_aliases
		. "$1" >/dev/null 2>&1
		alias
		printf "EXPORT ANTHROPIC_MODEL=%s\n" "$ANTHROPIC_MODEL"
		printf "EXPORT ANTHROPIC_DEFAULT_FABLE_MODEL=%s\n" "$ANTHROPIC_DEFAULT_FABLE_MODEL"
		printf "EXPORT ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n" "$ANTHROPIC_DEFAULT_OPUS_MODEL"
	' _ "$2"
}

# check_rows <bash> <shared.bash>: print one line for each fault. No output means no fault.
check_rows() {
	local out row name src effort perm def id want eff known
	out="$(dump "$1" "$2")"
	known=" "
	for row in "${ROWS[@]}"; do
		IFS='|' read -r name src effort perm <<EOF
$row
EOF
		known="$known$name "
		def="$(printf '%s\n' "$out" | sed -n "s/^alias $name='\(.*\)'\$/\1/p")"
		if [ -z "$def" ]; then
			echo "$name: not defined"
			continue
		fi
		id="$(printf '%s\n' "$def" | sed -n 's/.*--model \([^ ]*\).*/\1/p')"
		case "$src" in
			literal:*) want="${src#literal:}" ;;
			*) want="$(printf '%s\n' "$out" | sed -n "s/^EXPORT $src=//p")" ;;
		esac
		[ "$id" = "$want" ] || echo "$name: model '$id', expected '$want'"
		eff="$(printf '%s\n' "$def" | sed -n 's/^CLAUDE_CODE_EFFORT_LEVEL=\([^ ]*\) .*/\1/p')"
		[ "$eff" = "$effort" ] || echo "$name: effort '$eff', expected '$effort'"
		case "$def" in
			*"--permission-mode $perm"*) ;;
			*) echo "$name: the permission mode is not $perm" ;;
		esac
	done
	# Every claude-* alias in the file needs a row.
	for name in $(printf '%s\n' "$out" | sed -n "s/^alias \(claude-[^=]*\)=.*/\1/p"); do
		case "$known" in
			*" $name "*) ;;
			*) echo "$name: defined but has no row in this test" ;;
		esac
	done
}

for SH in /bin/bash "$(command -v bash)"; do
	# shellcheck disable=SC2016 # the given bash expands $BASH_VERSION, not this shell
	VER="$("$SH" -c 'printf %s "$BASH_VERSION"')"
	echo "--- aliases under $SH ($VER)"
	assert_eq "1.1 every claude-* alias matches its row" "" "$(check_rows "$SH" "$SHARED_BASH")"
	assert_eq "1.2 the default model stays opusplan" "opusplan" "$(dump "$SH" "$SHARED_BASH" | sed -n 's/^EXPORT ANTHROPIC_MODEL=//p')"
done

echo "--- fail-to-fail: broken copies of shared.bash are reported"
# 2.1: one opus alias names another model than the export.
sed '/^alias claude-opus-turbo=/s/claude-opus-5-5/claude-opus-4-6/' "$SHARED_BASH" >"$TMPD/stale-alias.bash"
assert_eq "2.1 an alias with a stale model id is reported" "claude-opus-turbo: model 'claude-opus-4-6', expected 'claude-opus-5-5'" \
	"$(check_rows "$(command -v bash)" "$TMPD/stale-alias.bash")"
# 2.2: the export moves on and the aliases stay behind.
sed 's/^export ANTHROPIC_DEFAULT_OPUS_MODEL=.*/export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-9-9"/' "$SHARED_BASH" >"$TMPD/stale-export.bash"
assert_eq "2.2 a bumped export leaves three opus aliases reported" 3 \
	"$(check_rows "$(command -v bash)" "$TMPD/stale-export.bash" | grep -c "expected 'claude-opus-9-9'")"
# 2.3: an alias that nobody listed.
{
	cat "$SHARED_BASH"
	printf "alias claude-extra='claude --model opusplan --permission-mode bypassPermissions'\n"
} >"$TMPD/extra-alias.bash"
assert_eq "2.3 an alias without a row is reported" "claude-extra: defined but has no row in this test" \
	"$(check_rows "$(command -v bash)" "$TMPD/extra-alias.bash")"
# 2.4: an alias without the --model flag would not beat the exported ANTHROPIC_MODEL.
sed "/^alias claude-opus=/s/ --model claude-opus-5-5//" "$SHARED_BASH" >"$TMPD/no-flag.bash"
assert_eq "2.4 an alias without --model is reported" "claude-opus: model '', expected 'claude-opus-5-5'" \
	"$(check_rows "$(command -v bash)" "$TMPD/no-flag.bash")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
