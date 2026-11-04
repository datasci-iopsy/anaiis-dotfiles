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
if ! command -v brew >/dev/null 2>&1; then
	[ "$verb" = refresh ] || echo "brew not found -- install Homebrew first: https://brew.sh"
	exit 0
fi

if [ "$verb" = refresh ]; then
	STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/brewfile-check.stamp"
	[ -f "$BREWFILE" ] || exit 0
	[ -w "${HOMEBREW_PREFIX:-/opt/homebrew}" ] || exit 0
	if [ -f "$STAMP" ]; then
		mtime="$(stat -c %Y "$STAMP" 2>/dev/null || stat -f %m "$STAMP" 2>/dev/null || echo 0)"
		[ $(($(date +%s) - mtime)) -gt 86400 ] || exit 0
	fi
	mkdir -p "$(dirname "$STAMP")"
	touch "$STAMP"
fi

# merge_dump: append the entries of a fresh `brew bundle dump` whose key is absent from the
# Brewfile. Sets ADDED to the number of lines appended. Returns 1 when brew fails.
merge_dump() {
	local tmpd
	tmpd="$(mktemp -d "${TMPDIR:-/tmp}/brew-sync.XXXXXX")" || return 1
	# The target path is new, so brew needs no force flag, and it never overwrites the Brewfile.
	if ! brew bundle dump --no-describe --file="$tmpd/dump" >/dev/null 2>&1; then
		rm -rf "$tmpd"
		return 1
	fi
	awk '
		function key(l) {
			sub(/^[ \t]+/, "", l)
			return match(l, /^[a-z_]+ "[^"]*"/) ? substr(l, RSTART, RLENGTH) : ""
		}
		NR == FNR { seen[key($0)] = 1; next }
		{ k = key($0); if (k != "" && !(k in seen)) { seen[k] = 1; print } }
	' "$BREWFILE" "$tmpd/dump" >"$tmpd/added"
	ADDED="$(grep -c . "$tmpd/added" || true)"
	if [ "$ADDED" -gt 0 ]; then
		[ -z "$(tail -c 1 "$BREWFILE")" ] || echo >>"$BREWFILE"
		cat "$tmpd/added" >>"$BREWFILE"
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
			echo "brew bundle dump failed; Brewfile unchanged" >&2
			exit 1
		}
		echo "Brewfile updated at $BREWFILE ($ADDED added)"
		;;
	refresh)
		if merge_dump && [ "$ADDED" -gt 0 ]; then
			echo "[dotfiles] Brewfile refreshed from installed packages; commit it from the dotfiles repo."
		fi
		;;
	*)
		echo "Usage: brew-sync.sh <install|check|dump|refresh>"
		exit 1
		;;
esac
