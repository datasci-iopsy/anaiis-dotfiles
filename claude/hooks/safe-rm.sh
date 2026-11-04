#!/usr/bin/env bash
# safe-rm.sh -- run-time guard for rm. Source this file once per shell; do not run it.
#
# bash-guard.sh rewrites an eligible compound command so that the command starts by sourcing this
# file. After that, `rm` and `mkdir` in the command are the functions below. Each function checks
# every operand AFTER the shell has expanded it (variables, globs), so it sees the real path. It
# deletes (or creates) nothing unless every operand is inside a root.
#
# Input (plain shell variables, set before the file is sourced):
#   __SAFE_RM_CWD       Absolute path of the working directory. Required. If it is empty, rm refuses
#                       every operand.
#   __SAFE_RM_SCRATCH   Absolute path of the session scratchpad. Optional. If it is empty, that root is off.
#
# Source time: the file copies every input once and makes the copies read-only. The inputs are the two
# variables above, the physical HOME and TMPDIR, and the absolute paths of the real rm and mkdir
# programs (found with `type -P` before the functions exist). The functions read only those copies.
# They never read HOME, TMPDIR, PATH, or PWD at call time, so a later statement that assigns one of
# them (a loop variable, `printf -v`, `PATH=`) cannot move a root or change which program runs. If no
# rm or no mkdir program exists on PATH, the file returns 1 and defines no function. The caller then
# exits.
#
# Deletion roots (each check uses the resolved physical path, so a symlink in the path cannot lead out):
#   1. A strict descendant of the scratchpad.
#   2. Inside the working directory: a disposable folder or a path inside one (.ruff_cache,
#      .pytest_cache, .mypy_cache, .tox, __pycache__, .venv, node_modules, dist, build, .next,
#      coverage), a strict descendant of tests/fixtures, or a strict descendant of tmp. A path
#      under tmp/worktrees is refused unless it is inside a disposable folder. These roots are off
#      when the working directory is HOME, a parent of HOME, or the root folder.
#   3. A tmp.* folder under TMPDIR, or a path inside one (the result of mktemp -d).
# Always refused: the root folder, the home folder, the working directory and its parents, any path
# with a .git component, any path with a .. component, any flag outside -r -R -f -v -d --recursive
# --force --verbose --dir --, and a trailing slash on a symlink.
#
# Flags end at the first operand or at --, as in BSD rm. A later word that looks like a flag is an
# operand and is checked as a path.
#
# mkdir uses the same roots and the same refusals for the path it creates (the parent is resolved
# physically; with -p, the nearest existing ancestor is resolved). It allows only the flags -p and -v
# (alone or together, such as -pv) and --.
#
# On a refusal the function prints the reason, changes nothing, and EXITS the shell with status 1,
# so no later statement of the command runs. To delete a path that is outside the roots, run the
# delete as its own call with a literal path. bash-guard.sh then asks the user. The real program gets
# the vetted flags, then --, then the resolved physical paths: the list that is checked is the list
# that is deleted (or created).

__safe_rm_say() {
	printf 'safe-rm: %s\n' "$1" >&2
	printf 'safe-rm: nothing was deleted and the command stopped. Run the delete as its own call with a literal path to get a prompt.\n' >&2
}

# __safe_rm_phys <folder>: print the physical path of an existing folder, or print nothing.
__safe_rm_phys() {
	[ -n "$1" ] || return 1
	(cd "$1" 2>/dev/null && pwd -P)
}

# __safe_rm_resolve <path>: print the absolute path with every symlink in the PARENT path resolved.
# The last component stays as written, because rm removes a symlink itself and does not follow it.
# A relative path starts at the physical working directory (pwd -P), never at $PWD.
# Return 1 for a path with a .. component.
__safe_rm_resolve() {
	local p="$1" dir base probe rest res here sl=/ dot=/./
	case "$p" in
		/*) ;;
		*)
			here="$(pwd -P)" || return 1
			p="$here/$p"
			;;
	esac
	case "/$p/" in
		*/../*) return 1 ;;
	esac
	# The slash and the pattern sit in variables on purpose: bash 3.2 keeps the backslash of an
	# escaped replacement (${p//\/\//\/} gives /a\/b), and a variable gives the same result on every bash.
	while :; do
		case "$p" in
			*//*) p="${p//$sl$sl/$sl}" ;;
			*/./*) p="${p//$dot/$sl}" ;;
			*/.) p="${p%/.}" ;;
			*) break ;;
		esac
	done
	while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do
		p="${p%/}"
	done
	if [ "$p" = "/" ]; then
		printf '/\n'
		return 0
	fi
	dir="${p%/*}"
	base="${p##*/}"
	[ -n "$dir" ] || dir="/"
	probe="$dir"
	rest=""
	while [ ! -d "$probe" ]; do
		rest="/${probe##*/}$rest"
		probe="${probe%/*}"
		[ -n "$probe" ] || probe="/"
	done
	probe="$(__safe_rm_phys "$probe")" || return 1
	[ -n "$probe" ] || return 1
	res="$probe"
	[ "$res" = "/" ] && res=""
	printf '%s%s/%s\n' "$res" "$rest" "$base"
}

# __safe_rm_check <resolved-path>: return 0 when the path is inside a deletion root.
# Otherwise print the reason and return 1. It reads only the copies made at source time.
__safe_rm_check() {
	local path="$1" rel
	if [ -z "$__SAFE_RM_CWDP" ] || [ "$__SAFE_RM_CWDP" = "/" ]; then
		echo "no working directory was given, so no root is known"
		return 1
	fi
	if [ "$path" = "/" ]; then
		echo "the root folder is never deleted"
		return 1
	fi
	if [ -n "$__SAFE_RM_HOMEP" ] && [ "$path" = "$__SAFE_RM_HOMEP" ]; then
		echo "the home folder is never deleted"
		return 1
	fi
	case "$__SAFE_RM_CWDP/" in
		"$path"/*)
			echo "the working directory and its parents are never deleted"
			return 1
			;;
	esac
	case "$path/" in
		*/.git/*)
			echo "a .git folder is never deleted"
			return 1
			;;
	esac

	if [ -n "$__SAFE_RM_SCRATCHP" ] && [ "$__SAFE_RM_SCRATCHP" != "/" ]; then
		case "$path" in
			"$__SAFE_RM_SCRATCHP"/?*) return 0 ;;
		esac
	fi

	if [ -n "$__SAFE_RM_TMPP" ] && [ "$__SAFE_RM_TMPP" != "/" ]; then
		case "$path" in
			"$__SAFE_RM_TMPP"/tmp.?*) return 0 ;;
		esac
	fi

	if [ "$__SAFE_RM_CWDROOTS" = 1 ]; then
		case "$path" in
			"$__SAFE_RM_CWDP"/?*)
				rel="${path#"$__SAFE_RM_CWDP"/}"
				case "/$rel/" in
					*/.ruff_cache/* | */.pytest_cache/* | */.mypy_cache/* | */.tox/* | */__pycache__/* | */.venv/* | */node_modules/* | */dist/* | */build/* | */.next/* | */coverage/*)
						return 0
						;;
				esac
				case "$rel" in
					tests/fixtures/?*) return 0 ;;
					tmp/worktrees | tmp/worktrees/*) ;;
					tmp/?*) return 0 ;;
				esac
				;;
		esac
	fi
	echo "outside the deletion roots (scratchpad, disposable folders, mktemp folders)"
	return 1
}

# __safe_rm_parse <short-letters> <long-flags> <args...>: split the arguments into the caller's
# flags and ops arrays. Flags end at the first operand or at --. A flag outside the allowed set
# stops the whole command. The arrays belong to the caller (dynamic scope).
__safe_rm_parse() {
	local letters="$1" longs="$2" a parsing=1 bad
	bad="*[!$letters]*"
	shift 2
	for a in "$@"; do
		if [ "$parsing" -eq 1 ]; then
			case "$a" in
				--)
					parsing=0
					continue
					;;
				-?*)
					case " $longs " in
						*" $a "*)
							flags+=("$a")
							continue
							;;
					esac
					# $bad is a glob on purpose.
					# shellcheck disable=SC2254
					case "${a#-}" in
						$bad)
							__safe_rm_say "refused flag '$a': only the flag letters $letters and -- are allowed here"
							exit 1
							;;
					esac
					flags+=("$a")
					continue
					;;
			esac
			parsing=0
		fi
		ops+=("$a")
	done
}

# __safe_rm_vet <operands...>: check every operand, then append the resolved paths to the caller's
# paths array. The first refusal stops the whole command, before the caller changes anything.
__safe_rm_vet() {
	local a b resolved reason
	for a in "$@"; do
		if [ -z "$a" ]; then
			__safe_rm_say "refused '': the operand is empty"
			exit 1
		fi
		case "$a" in
			*/)
				b="$a"
				while [ "${#b}" -gt 1 ] && [ "${b%/}" != "$b" ]; do
					b="${b%/}"
				done
				if [ -L "$b" ]; then
					__safe_rm_say "refused '$a': a trailing slash on a symlink"
					exit 1
				fi
				;;
		esac
		resolved="$(__safe_rm_resolve "$a")" || {
			__safe_rm_say "refused '$a': the path has a .. component or cannot be resolved"
			exit 1
		}
		reason="$(__safe_rm_check "$resolved")" || {
			__safe_rm_say "refused '$a' ($resolved): $reason"
			exit 1
		}
		paths+=("$resolved")
	done
}

# Source-time capture. This runs once, before the functions exist, and the values never change.
# The roots are computed here and not for each operand (one fork each, not one per operand).
__SAFE_RM_REAL="$(type -P rm)"
[ -n "$__SAFE_RM_REAL" ] || return 1
__SAFE_RM_REALMKDIR="$(type -P mkdir)"
[ -n "$__SAFE_RM_REALMKDIR" ] || return 1
__SAFE_RM_CWDP="$(__safe_rm_phys "${__SAFE_RM_CWD:-}")"
__SAFE_RM_SCRATCHP="$(__safe_rm_phys "${__SAFE_RM_SCRATCH:-}")"
__SAFE_RM_HOMEP="$(__safe_rm_phys "${HOME:-}")"
__SAFE_RM_TMPP="$(__safe_rm_phys "${TMPDIR:-/tmp}")"
__SAFE_RM_CWDROOTS=1
if [ -n "$__SAFE_RM_HOMEP" ]; then
	case "$__SAFE_RM_HOMEP/" in
		"$__SAFE_RM_CWDP"/*) __SAFE_RM_CWDROOTS=0 ;;
	esac
fi
readonly __SAFE_RM_CWD __SAFE_RM_SCRATCH __SAFE_RM_REAL __SAFE_RM_REALMKDIR __SAFE_RM_CWDP __SAFE_RM_SCRATCHP \
	__SAFE_RM_HOMEP __SAFE_RM_TMPP __SAFE_RM_CWDROOTS

rm() {
	local IFS=$' \t\n'
	local -a flags ops paths
	flags=()
	ops=()
	paths=()
	__safe_rm_parse 'rRfvd' '--recursive --force --verbose --dir' "$@"
	if [ "${#ops[@]}" -eq 0 ]; then
		"$__SAFE_RM_REAL" "$@"
		return $?
	fi
	__safe_rm_vet "${ops[@]}"
	# ${flags[@]+...} keeps an empty array safe under set -u on bash 3.2.
	"$__SAFE_RM_REAL" ${flags[@]+"${flags[@]}"} -- "${paths[@]}"
}

mkdir() {
	local IFS=$' \t\n'
	local -a flags ops paths
	flags=()
	ops=()
	paths=()
	__safe_rm_parse 'pv' '' "$@"
	if [ "${#ops[@]}" -eq 0 ]; then
		"$__SAFE_RM_REALMKDIR" "$@"
		return $?
	fi
	__safe_rm_vet "${ops[@]}"
	"$__SAFE_RM_REALMKDIR" ${flags[@]+"${flags[@]}"} -- "${paths[@]}"
}
