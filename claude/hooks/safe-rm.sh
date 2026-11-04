#!/usr/bin/env bash
# safe-rm.sh -- run-time guard for rm. Source this file; do not run it.
#
# bash-guard.sh rewrites an eligible compound command so that the command starts by sourcing this
# file. After that, `rm` in the command is the function below. The function checks every operand
# AFTER the shell has expanded it (variables, globs), so it sees the real path. It deletes nothing
# unless every operand is inside a deletion root.
#
# Input (plain shell variables, set before the file is sourced):
#   __SAFE_RM_CWD       Absolute path of the working directory. Required. If it is empty, rm refuses
#                       every operand.
#   __SAFE_RM_SCRATCH   Absolute path of the session scratchpad. Optional. If it is empty, that root is off.
#
# Deletion roots (each check uses the resolved physical path, so a symlink in the path cannot lead out):
#   1. A strict descendant of the scratchpad.
#   2. Inside the working directory: a disposable folder or a path inside one (.ruff_cache,
#      .pytest_cache, .mypy_cache, .tox, __pycache__, .venv, node_modules, dist, build, .next,
#      coverage), a strict descendant of tests/fixtures, or a strict descendant of tmp. A path
#      under tmp/worktrees is refused unless it is inside a disposable folder.
#   3. A tmp.* folder under TMPDIR, or a path inside one (the result of mktemp -d).
# Always refused: the root folder, the home folder, the working directory and its parents, any path
# with a .git component, any path with a .. component, any flag outside -r -R -f -v -d --recursive
# --force --verbose --dir --, and a trailing slash on a symlink.
#
# On a refusal the function prints the reason, deletes nothing, and returns 1. To delete a path that
# is outside the roots, run the delete as its own call with a literal path. bash-guard.sh then asks
# the user.

__safe_rm_say() {
	printf 'safe-rm: %s\n' "$1" >&2
	printf 'safe-rm: nothing was deleted. Run the delete as its own call with a literal path to get a prompt.\n' >&2
}

# __safe_rm_phys <folder>: print the physical path of an existing folder, or print nothing.
__safe_rm_phys() {
	[ -n "$1" ] || return 1
	(cd "$1" 2>/dev/null && pwd -P)
}

# __safe_rm_resolve <path>: print the absolute path with every symlink in the PARENT path resolved.
# The last component stays as written, because rm removes a symlink itself and does not follow it.
# Return 1 for a path with a .. component.
__safe_rm_resolve() {
	local p="$1" dir base probe rest res sl=/ dot=/./
	case "$p" in
		/*) ;;
		*) p="$PWD/$p" ;;
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
# Otherwise print the reason and return 1.
__safe_rm_check() {
	local path="$1" cwd scratch home tmp rel
	cwd="$(__safe_rm_phys "${__SAFE_RM_CWD:-}")"
	if [ -z "$cwd" ] || [ "$cwd" = "/" ]; then
		echo "no working directory was given, so no root is known"
		return 1
	fi
	if [ "$path" = "/" ]; then
		echo "the root folder is never deleted"
		return 1
	fi
	home="$(__safe_rm_phys "${HOME:-}")"
	if [ -n "$home" ] && [ "$path" = "$home" ]; then
		echo "the home folder is never deleted"
		return 1
	fi
	case "$cwd/" in
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

	scratch="$(__safe_rm_phys "${__SAFE_RM_SCRATCH:-}")"
	if [ -n "$scratch" ] && [ "$scratch" != "/" ]; then
		case "$path" in
			"$scratch"/?*) return 0 ;;
		esac
	fi

	tmp="$(__safe_rm_phys "${TMPDIR:-/tmp}")"
	if [ -n "$tmp" ] && [ "$tmp" != "/" ]; then
		case "$path" in
			"$tmp"/tmp.?*) return 0 ;;
		esac
	fi

	case "$path" in
		"$cwd"/?*)
			rel="${path#"$cwd"/}"
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
	echo "outside the deletion roots (scratchpad, disposable folders, mktemp folders)"
	return 1
}

rm() {
	local a b seen_dd=0 resolved reason
	local -a ops
	ops=()
	for a in "$@"; do
		if [ "$seen_dd" -eq 0 ]; then
			case "$a" in
				--)
					seen_dd=1
					continue
					;;
				--recursive | --force | --verbose | --dir) continue ;;
				-?*)
					case "${a#-}" in
						*[!rRfvd]*)
							__safe_rm_say "refused flag '$a': only -r -R -f -v -d and their long forms are allowed"
							return 1
							;;
					esac
					continue
					;;
			esac
		fi
		ops+=("$a")
	done
	if [ "${#ops[@]}" -eq 0 ]; then
		command rm "$@"
		return $?
	fi
	for a in "${ops[@]}"; do
		if [ -z "$a" ]; then
			__safe_rm_say "refused '': the operand is empty"
			return 1
		fi
		case "$a" in
			*/)
				b="$a"
				while [ "${#b}" -gt 1 ] && [ "${b%/}" != "$b" ]; do
					b="${b%/}"
				done
				if [ -L "$b" ]; then
					__safe_rm_say "refused '$a': a trailing slash on a symlink"
					return 1
				fi
				;;
		esac
		resolved="$(__safe_rm_resolve "$a")" || {
			__safe_rm_say "refused '$a': the path has a .. component or cannot be resolved"
			return 1
		}
		reason="$(__safe_rm_check "$resolved")" || {
			__safe_rm_say "refused '$a' ($resolved): $reason"
			return 1
		}
	done
	command rm "$@"
}
