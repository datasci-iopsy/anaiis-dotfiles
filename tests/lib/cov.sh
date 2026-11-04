#!/usr/bin/env bash
# tests/lib/cov.sh -- approximate line coverage for shell scripts, built from xtrace. Source it.
#
# Use:
#   . "$REPO_DIR/tests/lib/cov.sh"
#   cov_begin "$TMPDIR/cov.log"      # trace this shell and every child bash process
#   bash "$REPO_DIR/claude/scripts/x.sh" ...
#   cov_end
#   cov_report "$REPO_DIR/claude/scripts/x.sh"      # COV_VERBOSE=1 also lists the missed lines
#
# Needs bash 4.1 or later (BASH_XTRACEFD). On an older bash, cov_begin prints one SKIP line and the
# other functions do nothing, so a suite still passes on bash 3.2. Do not start /bin/bash 3.2 as a
# child of a traced test: it ignores BASH_XTRACEFD and writes the trace to standard error.
#
# How it works: cov_begin opens file descriptor 9 on the log, sets BASH_XTRACEFD=9 and a PS4 that
# prints the source file and line number, and sets BASH_ENV to a file that turns on xtrace in each
# child bash process. cov_report counts the executable lines of a script and the lines that the
# log shows as run.
#
# This is an approximation. It counts lines, not branches. A multi-line quoted string can add or
# hide a line. Use it to find code that no test runs, not as a pass or fail gate.

cov_enabled() {
	local ver="${COV_FAKE_BASH_VERSION:-${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}}"
	local major="${ver%%.*}" minor="${ver#*.}"
	[ "$major" -gt 4 ] || { [ "$major" -eq 4 ] && [ "$minor" -ge 1 ]; }
}

cov_begin() {
	COV_LOG=""
	if ! cov_enabled; then
		echo "SKIP cov: needs bash 4.1 or later"
		return 0
	fi
	COV_LOG="$1"
	: >>"$COV_LOG"
	printf 'set -x\n' >"$COV_LOG.env"
	exec 9>>"$COV_LOG"
	export BASH_XTRACEFD=9
	export PS4='+COV|${BASH_SOURCE[0]:-}|${LINENO:-}|'
	export BASH_ENV="$COV_LOG.env"
	set -x
}

cov_end() {
	[ -n "${COV_LOG:-}" ] || return 0
	set +x
	unset BASH_ENV BASH_XTRACEFD
	exec 9>&-
}

# cov__norm <file>: print the absolute path of the file with every symlink resolved.
cov__norm() {
	local p="$1" t
	while [ -L "$p" ]; do
		t="$(readlink "$p")"
		case "$t" in
			/*) p="$t" ;;
			*) p="$(dirname "$p")/$t" ;;
		esac
	done
	(cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$p")")
}

# cov__exec_lines <file>: print the line number of each executable line, one per line.
# Skipped: blank lines, comments, heredoc bodies, line continuations, function headers, case
# patterns, and lines that only close a block (fi, done, esac, else, then, do, braces, ;;).
cov__exec_lines() {
	awk '
		BEGIN {
			q = "\047"
			hdre = "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*[\"" q "]?"
		}
		hd != "" {
			t = $0
			sub(/^[ \t]+/, "", t)
			if (t == hd) hd = ""
			next
		}
		cont {
			t = $0
			sub(/[ \t]+$/, "", t)
			cont = (t ~ /\\$/)
			next
		}
		{
			t = $0
			sub(/^[ \t]+/, "", t)
			sub(/[ \t]+$/, "", t)
		}
		t == "" || t ~ /^#/ { next }
		t ~ /^(fi|done|esac|else|then|do|\{|\}|;;|\))$/ { next }
		t ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{?$/ { next }
		t ~ /^[^()]*\)$/ { next }
		{
			print NR
			if (t ~ /\\$/) cont = 1
			u = t
			gsub(/<<</, "", u)
			if (match(u, hdre)) {
				w = substr(u, RSTART, RLENGTH)
				sub("^<<-?[ \t]*[\"" q "]?", "", w)
				sub("[\"" q "]$", "", w)
				hd = w
			}
		}
	' "$1"
}

# cov__hits <normalized-file>: print the line numbers that the log shows as run, one per line.
cov__hits() {
	local want="$1" p
	grep -o 'COV|[^|]*|[0-9]*|' "$COV_LOG" | awk -F'|' '{print $2}' | LC_ALL=C sort -u | while IFS= read -r p; do
		if [ "$(cov__norm "$p")" = "$want" ]; then
			grep -F "COV|$p|" "$COV_LOG" | awk -F'|' -v p="$p" '$2 == p {print $3}'
		fi
	done | LC_ALL=C sort -u
}

# cov_report <file>...: print "cov: <file> <hit>/<total> <percent>%" for each file.
cov_report() {
	[ -n "${COV_LOG:-}" ] || return 0
	local f real tmp total hit pct
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/cov.XXXXXX")" || return 1
	echo "cov: approximate line coverage from xtrace (lines, not branches)"
	for f in "$@"; do
		real="$(cov__norm "$f")"
		cov__exec_lines "$f" | LC_ALL=C sort >"$tmp/exec"
		cov__hits "$real" >"$tmp/hits"
		LC_ALL=C comm -12 "$tmp/exec" "$tmp/hits" >"$tmp/hit"
		total="$(grep -c . "$tmp/exec")"
		hit="$(grep -c . "$tmp/hit")"
		pct=0
		[ "$total" -gt 0 ] && pct=$((hit * 100 / total))
		printf 'cov: %s %s/%s %s%%\n' "$f" "$hit" "$total" "$pct"
		if [ -n "${COV_VERBOSE:-}" ]; then
			printf 'cov:   missed: %s\n' "$(LC_ALL=C comm -23 "$tmp/exec" "$tmp/hit" | sort -n | tr '\n' ' ')"
		fi
	done
	rm -rf "$tmp"
}
