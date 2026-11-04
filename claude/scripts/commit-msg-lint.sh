#!/usr/bin/env bash
# commit-msg-lint.sh -- check a commit message against the house rubric
#
# Usage:
#   commit-msg-lint.sh <message-file>   check the message
#   commit-msg-lint.sh --types          print the allowed types, one per line
#
# Output: one stderr line per violation, in the form "commit-msg-lint: R<n> <reason>".
# Exit 0 when the message passes, 1 on a violation, 2 on a usage error.
#
# Rules (the rubric is in claude/rules/git.md):
#   R0  the message is not empty after comments are removed
#   R1  the type is one of the allowed types
#   R2  the type and the scope are lowercase
#   R3  the scope is ( then [a-z0-9][a-z0-9._/-]* then )
#   R4  an optional ! sits immediately before the colon
#   R5  the prefix ends with a colon and one space, then a non-space character
#   R6  the first line is at most 72 characters
#   R7  the first line has no trailing period
#   R8  the first line has no standalone word WIP (any case)
#   R9  when a body exists, line 2 is blank
#   R10 a footer token in the last paragraph uses hyphens; BREAKING CHANGE is uppercase
#   R11 a BREAKING CHANGE footer needs the ! before the colon
#
# Exempt subjects: "Merge ", Revert "...", "fixup! ", "squash! ".
# Not enforced: the lowercase first letter of the description, and the 72-character body wrap.
#
# Pure bash 3.2 plus tr: no associative arrays, no mapfile, no ${var,,}.

set -u

TYPES="feat fix build chore ci docs style refactor perf test revert"

RE_SCOPE='^[a-z0-9][a-z0-9._/-]*$'
RE_SEP='^: [^ ]'
RE_WIP='(^|[^A-Za-z0-9_])[Ww][Ii][Pp]($|[^A-Za-z0-9_])'
# A footer label: one to three words (letters, digits, hyphens) before ": ".
RE_LABEL='^([A-Za-z][A-Za-z0-9-]*( [A-Za-z0-9-]+){0,2}): '

if [ "${1:-}" = "--types" ]; then
	for t in $TYPES; do
		echo "$t"
	done
	exit 0
fi

msg_file="${1:-}"
if [ ! -f "$msg_file" ]; then
	echo "usage: commit-msg-lint.sh <message-file> | --types" >&2
	exit 2
fi

bad=0
fail() {
	printf 'commit-msg-lint: %s %s\n' "$1" "$2" >&2
	bad=1
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Read the message as git cleans it: skip comment lines, strip trailing
# whitespace, and drop leading and trailing blank lines.
lines=()
count=0
started=0
while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in
		'#'*) continue ;;
	esac
	line="${line%"${line##*[![:space:]]}"}"
	if [ "$started" -eq 0 ] && [ -z "$line" ]; then
		continue
	fi
	started=1
	lines[count]="$line"
	count=$((count + 1))
done <"$msg_file"
while [ "$count" -gt 0 ] && [ -z "${lines[count - 1]}" ]; do
	count=$((count - 1))
done

# R0
if [ "$count" -eq 0 ]; then
	fail R0 "the message is empty; comment lines do not count"
	exit 1
fi

first="${lines[0]}"

# Exempt subjects: git writes them, so the rubric does not apply.
case "$first" in
	'Merge '* | 'fixup! '* | 'squash! '*) exit 0 ;;
	'Revert "'*'"') exit 0 ;;
esac

# Split the first line into type, optional scope, optional !, and the rest.
type="${first%%[(!: ]*}"
rest="${first#"$type"}"
type_lc=$(lower "$type")
parse_ok=1
bang=0

# R1
if [ -z "$type" ]; then
	fail R1 "the type is missing; use one of: $TYPES"
else
	case " $TYPES " in
		*" $type_lc "*) ;;
		*) fail R1 "type '$type' is not allowed; use one of: $TYPES" ;;
	esac
fi

# R2 (type)
if [ -n "$type" ] && [ "$type" != "$type_lc" ]; then
	fail R2 "type '$type' must be lowercase"
fi

# R3 and R2 (scope)
if [[ $rest == '('* ]]; then
	if [[ $rest == *')'* ]]; then
		scope="${rest#\(}"
		scope="${scope%%)*}"
		rest="${rest#*)}"
		scope_lc=$(lower "$scope")
		if [ "$scope" != "$scope_lc" ]; then
			fail R2 "scope '$scope' must be lowercase"
		fi
		if ! [[ $scope_lc =~ $RE_SCOPE ]]; then
			fail R3 "scope '$scope' must match [a-z0-9][a-z0-9._/-]*"
		fi
	else
		fail R3 "the scope has no closing parenthesis"
		parse_ok=0
	fi
fi

# R4
if [ "$parse_ok" -eq 1 ] && [[ $rest == '!'* ]]; then
	bang=1
	rest="${rest#!}"
	if [[ $rest != ':'* ]]; then
		fail R4 "write one ! immediately before the colon"
		parse_ok=0
	fi
fi

# R5
if [ "$parse_ok" -eq 1 ] && ! [[ $rest =~ $RE_SEP ]]; then
	fail R5 "the prefix must end with a colon and one space, then the description"
fi

# R6
if [ "${#first}" -gt 72 ]; then
	fail R6 "the first line has ${#first} characters; the limit is 72"
fi

# R7
if [[ $first == *. ]]; then
	fail R7 "the first line must not end with a period"
fi

# R8
if [[ $first =~ $RE_WIP ]]; then
	fail R8 "the first line must not contain WIP"
fi

# R9
if [ "$count" -ge 2 ] && [ -n "${lines[1]}" ]; then
	fail R9 "line 2 must be blank when the message has a body"
fi

# R10 and R11: footers sit in the last paragraph, which must follow a blank line.
breaking=0

# check_footer_token <label>: apply R10 to one footer label; note a breaking footer for R11.
check_footer_token() {
	local token="$1" token_lc
	case "$token" in
		'BREAKING CHANGE' | 'BREAKING-CHANGE')
			breaking=1
			return
			;;
	esac
	token_lc=$(lower "$token")
	case "$token_lc" in
		'breaking change' | 'breaking-change')
			fail R10 "write the footer token '$token' as BREAKING CHANGE or BREAKING-CHANGE, in uppercase"
			;;
		*' '*)
			fail R10 "footer token '$token' has a space; use hyphens, as in '${token// /-}:'"
			;;
	esac
}

last=$((count - 1))
start=$last
while [ "$start" -gt 0 ] && [ -n "${lines[start - 1]}" ]; do
	start=$((start - 1))
done
if [ "$start" -gt 0 ]; then
	i=$start
	while [ "$i" -le "$last" ]; do
		if [[ ${lines[i]} =~ $RE_LABEL ]]; then
			check_footer_token "${BASH_REMATCH[1]}"
		fi
		i=$((i + 1))
	done
fi
if [ "$breaking" -eq 1 ] && [ "$bang" -eq 0 ]; then
	fail R11 "a BREAKING CHANGE footer needs a ! before the colon in the first line"
fi

exit "$bad"
