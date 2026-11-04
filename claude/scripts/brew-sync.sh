#!/usr/bin/env bash
# Four verbs: install | check | dump | refresh
# install  -- brew bundle install (idempotent; safe to re-run on any machine)
# check    -- report drift between installed packages and Brewfile
# dump     -- add installed packages that the Brewfile lacks (never removes a line)
# refresh  -- run dump at most once per 24 hours; silent unless the file changed
#
# Several profiles share one Brewfile. dump and refresh only append entries whose key is new.
# The key is the type and the quoted name, for example: brew "pup". An existing line wins when
# the keys match, so `brew "pup", trusted: true` is never duplicated by `brew "pup"`.
# To remove an entry on purpose, edit the Brewfile by hand.
set -euo pipefail

CANONICAL="$HOME/anaiis-dotfiles"
BREWFILE="$CANONICAL/Brewfile"

verb="${1:-}"

# refresh runs from every shell start, so it stays silent unless it has work to do.
if [ "$verb" = refresh ]; then
	STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/brewfile-check.stamp"
	command -v brew >/dev/null 2>&1 || exit 0
	[ -f "$BREWFILE" ] || exit 0
	[ -w "${HOMEBREW_PREFIX:-/opt/homebrew}" ] || exit 0
	if [ -f "$STAMP" ]; then
		mtime="$(stat -c %Y "$STAMP" 2>/dev/null || stat -f %m "$STAMP" 2>/dev/null || echo 0)"
		[ $(($(date +%s) - mtime)) -gt 86400 ] || exit 0
	fi
	mkdir -p "$(dirname "$STAMP")"
	touch "$STAMP"
fi

if ! command -v brew >/dev/null 2>&1; then
	echo "brew not found -- install Homebrew first: https://brew.sh"
	exit 0
fi

# merge_dump: append the entries of a fresh `brew bundle dump` whose key is absent from the
# Brewfile. Sets ADDED to the number of lines appended. Returns 1 and sets FAIL_WHY when the
# Brewfile is missing or not writable, brew fails, or the merge or an append fails. The callers
# run it inside an if, where set -e does not apply, so every step checks its own status.
merge_dump() {
	local tmpd
	ADDED=0
	FAIL_WHY=""
	if [ ! -f "$BREWFILE" ] || [ ! -w "$BREWFILE" ]; then
		FAIL_WHY="Brewfile is missing or not writable: $BREWFILE"
		return 1
	fi
	tmpd="$(mktemp -d "${TMPDIR:-/tmp}/brew-sync.XXXXXX")" || {
		FAIL_WHY="could not create a temporary folder"
		return 1
	}
	# The target path is new, so brew needs no force flag, and it never overwrites the Brewfile.
	if ! brew bundle dump --no-describe --file="$tmpd/dump" >/dev/null 2>&1; then
		rm -rf "$tmpd"
		FAIL_WHY="brew bundle dump failed; Brewfile unchanged"
		return 1
	fi
	# FILENAME names the Brewfile records. NR == FNR would misread an empty Brewfile.
	awk '
		function key(l) {
			sub(/^[ \t]+/, "", l)
			return match(l, /^[a-z_]+ "[^"]*"/) ? substr(l, RSTART, RLENGTH) : ""
		}
		FILENAME == ARGV[1] { seen[key($0)] = 1; next }
		{ k = key($0); if (k != "" && !(k in seen)) { seen[k] = 1; print } }
	' "$BREWFILE" "$tmpd/dump" >"$tmpd/added" || {
		rm -rf "$tmpd"
		FAIL_WHY="could not merge the dump; Brewfile unchanged"
		return 1
	}
	ADDED="$(grep -c . "$tmpd/added" || true)"
	if [ "$ADDED" -gt 0 ]; then
		if [ -n "$(tail -c 1 "$BREWFILE")" ] && ! echo >>"$BREWFILE"; then
			rm -rf "$tmpd"
			ADDED=0
			FAIL_WHY="could not write to $BREWFILE"
			return 1
		fi
		if ! cat "$tmpd/added" >>"$BREWFILE"; then
			rm -rf "$tmpd"
			ADDED=0
			FAIL_WHY="could not append to $BREWFILE"
			return 1
		fi
	fi
	rm -rf "$tmpd"
}

case "$verb" in
	install)
		brew bundle install --file="$BREWFILE"
		;;
	check)
		brew bundle check --file="$BREWFILE" --verbose
		;;
	dump)
		merge_dump || {
			echo "brew-sync.sh dump: $FAIL_WHY" >&2
			exit 1
		}
		echo "Brewfile updated at $BREWFILE ($ADDED added)"
		;;
	refresh)
		# A shell start must not fail, so a failed refresh warns once and exits 0. The stamp is
		# already written, so the next try waits a day.
		if merge_dump; then
			if [ "$ADDED" -gt 0 ]; then
				echo "[dotfiles] Brewfile refreshed from installed packages; commit it from the dotfiles repo."
			fi
		else
			echo "[dotfiles] Brewfile refresh failed: $FAIL_WHY" >&2
		fi
		;;
	*)
		echo "Usage: brew-sync.sh <install|check|dump|refresh>"
		exit 1
		;;
esac
