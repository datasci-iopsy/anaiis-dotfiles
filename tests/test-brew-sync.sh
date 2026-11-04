#!/usr/bin/env bash
# tests/test-brew-sync.sh -- verify that claude/scripts/brew-sync.sh only ever ADDS Brewfile
# entries, and that the daily refresh in bash/shared.bash calls it instead of overwriting the file.
#
# Why this matters: several profiles share one Homebrew prefix and one Brewfile. The old refresh
# ran `brew bundle dump --force` and copied the result over the Brewfile. A profile that lacked a
# package (for example a per-user `go` or `uv` entry) deleted that entry for everyone (D-023, D-024).
#
# Safety: the suite runs brew-sync.sh only against a throwaway HOME that holds its own Brewfile, with
# a stub `brew` first on PATH. It never reads or writes the real Brewfile (case 8 proves it) and
# never sources shared.bash (case 7 reads the file as text).
#
# Env overrides, used for the fail-to-fail check:
#   BREW_SYNC    path of the script under test
#   SHARED_BASH  path of the shared.bash under test
#
# Usage: bash tests/test-brew-sync.sh        (COV=1 adds line coverage on bash 4.1 or later)

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREW_SYNC="${BREW_SYNC:-$REPO_DIR/claude/scripts/brew-sync.sh}"
SHARED_BASH="${SHARED_BASH:-$REPO_DIR/bash/shared.bash}"

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

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/test-brew-sync.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

if [ -n "${COV:-}" ]; then
	# shellcheck source-path=SCRIPTDIR
	# shellcheck source=lib/cov.sh
	. "$REPO_DIR/tests/lib/cov.sh"
	cov_begin "$TMPD/cov.log"
fi

# The real Brewfile of this checkout. No case may change it.
REAL_BREWFILE_SUM="$(cksum <"$REPO_DIR/Brewfile")"

H="$TMPD/home"
STUB="$TMPD/stub"
PREFIX="$TMPD/prefix"
DUMP="$TMPD/dump.txt"
CALLS="$TMPD/brew-calls.log"
BF="$H/anaiis-dotfiles/Brewfile"
STAMP="$H/.cache/brewfile-check.stamp"
mkdir -p "$H/anaiis-dotfiles" "$STUB" "$PREFIX"
unset XDG_CACHE_HOME

# Stub brew. It mimics `brew bundle dump`: write the fixture dump to --file, refuse to overwrite an
# existing file unless --force is given (as real brew does), and fail on any other argument.
cat >"$STUB/brew" <<'EOF'
#!/usr/bin/env bash
fail() {
	echo "stub brew: unexpected arguments: $*" >&2
	exit 64
}
# The pass-through verbs must name the Brewfile of the throwaway HOME, never another file.
case "$*" in
	"bundle install --file=$HOME/anaiis-dotfiles/Brewfile")
		echo install >>"$STUB_CALLS"
		exit 0
		;;
	"bundle check --file=$HOME/anaiis-dotfiles/Brewfile --verbose")
		echo check >>"$STUB_CALLS"
		exit 0
		;;
esac
[ "${1:-}" = bundle ] && [ "${2:-}" = dump ] || fail "$@"
shift 2
force=0
file=""
for arg in "$@"; do
	case "$arg" in
		--no-describe) ;;
		--force) force=1 ;;
		--file=*) file="${arg#--file=}" ;;
		*)
			echo "stub brew: unexpected argument: $arg" >&2
			exit 64
			;;
	esac
done
[ -n "$file" ] || {
	echo "stub brew: --file is required" >&2
	exit 64
}
if [ -e "$file" ] && [ "$force" -eq 0 ]; then
	echo "stub brew: $file exists; use --force" >&2
	exit 1
fi
cat "$STUB_DUMP" >"$file"
echo dump >>"$STUB_CALLS"
EOF
chmod +x "$STUB/brew"

# The five lines that the old refresh deleted (D-023), plus two ordinary lines.
write_brewfile() {
	cat >"$BF" <<'EOF'
tap "getsentry/tools"
brew "jq"
brew "datadog-labs/pack/pup", trusted: true
brew "getsentry/tools/sentry", trusted: true
brew "greptileai/tap/greptile", trusted: true
go "mvdan.cc/sh/v3/cmd/shfmt"
uv "shandy-sqlfmt"
cask "ghostty"
EOF
}

# Run a verb against the throwaway HOME with the stub brew first on PATH.
sync_run() {
	HOME="$H" HOMEBREW_PREFIX="$PREFIX" PATH="$STUB:$PATH" STUB_DUMP="$DUMP" STUB_CALLS="$CALLS" \
		"$BASH" "$BREW_SYNC" "$@"
}

line_count() { grep -cxF -- "$2" "$1" || true; }
calls() {
	if [ -f "$CALLS" ]; then grep -c dump "$CALLS" || true; else echo 0; fi
}

ORIGINAL="$TMPD/original.txt"
write_brewfile
cp "$BF" "$ORIGINAL"

echo "--- 1. dump keeps entries that the machine lacks"
# The dump holds only two of the eight lines. The old code overwrote the file with it.
printf 'brew "jq"\ncask "ghostty"\n' >"$DUMP"
sync_run dump >/dev/null 2>&1
assert_eq "1.1 file is byte-identical when the dump adds nothing" "$(cksum <"$ORIGINAL")" "$(cksum <"$BF")"
assert_eq "1.2 trusted pup line survives" 1 "$(line_count "$BF" 'brew "datadog-labs/pack/pup", trusted: true')"
assert_eq "1.3 trusted sentry line survives" 1 "$(line_count "$BF" 'brew "getsentry/tools/sentry", trusted: true')"
assert_eq "1.4 trusted greptile line survives" 1 "$(line_count "$BF" 'brew "greptileai/tap/greptile", trusted: true')"
assert_eq "1.5 go shfmt line survives" 1 "$(line_count "$BF" 'go "mvdan.cc/sh/v3/cmd/shfmt"')"
assert_eq "1.6 uv sqlfmt line survives" 1 "$(line_count "$BF" 'uv "shandy-sqlfmt"')"

echo "--- 2. dump appends a new entry"
printf 'brew "jq"\nbrew "newtool"\ncask "newapp"\n' >"$DUMP"
sync_run dump >/dev/null 2>&1
assert_eq "2.1 existing lines stay first, in order" "$(cksum <"$ORIGINAL")" "$(head -n 8 "$BF" | cksum)"
assert_eq "2.2 new brew entry is appended" 1 "$(line_count "$BF" 'brew "newtool"')"
assert_eq "2.3 new cask entry is appended" 1 "$(line_count "$BF" 'cask "newapp"')"
assert_eq "2.4 exactly two lines were added" 10 "$(grep -c . "$BF")"
assert_eq "2.5 new entries come after the old ones" 'brew "newtool"' "$(sed -n 9p "$BF")"

echo "--- 3. a second run changes nothing"
AFTER_FIRST="$(cksum <"$BF")"
sync_run dump >/dev/null 2>&1
assert_eq "3.1 file is identical after the second dump" "$AFTER_FIRST" "$(cksum <"$BF")"

echo "--- 4. option variants are not duplicated"
write_brewfile
printf 'brew "datadog-labs/pack/pup"\nbrew "getsentry/tools/sentry"\n' >"$DUMP"
sync_run dump >/dev/null 2>&1
assert_eq "4.1 file is unchanged when the dump holds only plain variants" "$(cksum <"$ORIGINAL")" "$(cksum <"$BF")"
assert_eq "4.2 one pup line remains" 1 "$(grep -c 'datadog-labs/pack/pup' "$BF")"
assert_eq "4.3 the trusted variant won" 1 "$(line_count "$BF" 'brew "datadog-labs/pack/pup", trusted: true')"

echo "--- 4b. a file without a final newline gets a clean append"
printf 'brew "jq"' >"$BF"
printf 'brew "jq"\nbrew "newtool"\n' >"$DUMP"
sync_run dump >/dev/null 2>&1
assert_eq "4b.1 the old last line and the new line are separate lines" 'brew "jq"|brew "newtool"' "$(paste -sd'|' "$BF")"

echo "--- 4c. a failing brew leaves the file alone and fails loud"
write_brewfile
mv "$STUB/brew" "$STUB/brew.off"
printf '#!/bin/sh\nexit 1\n' >"$STUB/brew"
chmod +x "$STUB/brew"
sync_run dump >/dev/null 2>&1
assert_eq "4c.1 dump exits non-zero when brew fails" 1 "$?"
assert_eq "4c.2 the file is unchanged" "$(cksum <"$ORIGINAL")" "$(cksum <"$BF")"
mv "$STUB/brew.off" "$STUB/brew"

echo "--- 4d. an empty Brewfile is filled"
# With awk's NR == FNR test, an empty first file made every dump record look like a Brewfile record.
: >"$BF"
printf 'brew "newtool"\ncask "newapp"\n' >"$DUMP"
out="$(sync_run dump 2>&1)"
assert_eq "4d.1 dump exits 0 on an empty Brewfile" 0 "$?"
assert_eq "4d.2 both entries were appended" 2 "$(grep -c . "$BF")"
assert_eq "4d.3 the message counts the two entries" "Brewfile updated at $BF (2 added)" "$out"

echo "--- 4e. a Brewfile that cannot be written fails loud"
write_brewfile
printf 'brew "newtool"\n' >"$DUMP"
chmod 444 "$BF"
if [ -w "$BF" ]; then
	echo "  SKIP  4e (this user ignores file modes)"
else
	out="$(sync_run dump 2>&1)"
	assert_eq "4e.1 dump exits 1 when the append fails" 1 "$?"
	assert_eq "4e.2 dump does not claim success" 0 "$(printf '%s' "$out" | grep -c 'Brewfile updated')"
	assert_eq "4e.3 the file is unchanged" "$(cksum <"$ORIGINAL")" "$(cksum <"$BF")"
fi
chmod 644 "$BF"

echo "--- 4f. dump fails loud when the Brewfile is missing"
mv "$BF" "$BF.off"
out="$(sync_run dump 2>&1)"
assert_eq "4f.1 dump exits 1 without a Brewfile" 1 "$?"
assert_eq "4f.2 dump does not claim success" 0 "$(printf '%s' "$out" | grep -c 'Brewfile updated')"
assert_eq "4f.3 no Brewfile was created" no "$([ -e "$BF" ] && echo yes || echo no)"
mv "$BF.off" "$BF"

echo "--- 5. refresh obeys the daily stamp"
write_brewfile
rm -f "$CALLS"
printf 'brew "jq"\nbrew "newtool"\n' >"$DUMP"
out="$(sync_run refresh 2>&1)"
assert_eq "5.1 refresh with no stamp exits 0" 0 "$?"
assert_eq "5.2 refresh with no stamp ran brew once" 1 "$(calls)"
assert_eq "5.3 refresh appended the new entry" 1 "$(line_count "$BF" 'brew "newtool"')"
assert_eq "5.4 refresh printed the commit hint" \
	'[dotfiles] Brewfile refreshed from installed packages; commit it from the dotfiles repo.' "$out"
assert_eq "5.5 refresh created the stamp" yes "$([ -f "$STAMP" ] && echo yes || echo no)"
AFTER_REFRESH="$(cksum <"$BF")"
printf 'brew "jq"\nbrew "newtool"\nbrew "another"\n' >"$DUMP"
out="$(sync_run refresh 2>&1)"
assert_eq "5.6 a fresh stamp skips the scan: brew not called again" 1 "$(calls)"
assert_eq "5.7 a fresh stamp leaves the file alone" "$AFTER_REFRESH" "$(cksum <"$BF")"
assert_eq "5.8 a fresh stamp prints nothing" "" "$out"
touch -t 200001010000 "$STAMP"
out="$(sync_run refresh 2>&1)"
assert_eq "5.9 a stamp older than 24 hours runs the scan" 2 "$(calls)"
assert_eq "5.10 the old stamp let the new entry in" 1 "$(line_count "$BF" 'brew "another"')"
assert_eq "5.11 the old stamp was touched" yes "$([ -z "$(find "$STAMP" -mmin +5)" ] && echo yes || echo no)"
touch -t 200001010000 "$STAMP"
out="$(sync_run refresh 2>&1)"
assert_eq "5.12 refresh stays silent when the file did not change" "" "$out"
assert_eq "5.13 refresh ran brew a third time" 3 "$(calls)"

echo "--- 6. refresh skips when a condition fails"
write_brewfile
rm -f "$CALLS" "$STAMP"
printf 'brew "newtool"\n' >"$DUMP"
out="$(HOME="$H" HOMEBREW_PREFIX="$TMPD/no-such-prefix" PATH="$STUB:$PATH" STUB_DUMP="$DUMP" STUB_CALLS="$CALLS" "$BASH" "$BREW_SYNC" refresh 2>&1)"
assert_eq "6.1 unwritable prefix: exit 0" 0 "$?"
assert_eq "6.2 unwritable prefix: brew not called" 0 "$(calls)"
assert_eq "6.3 unwritable prefix: file unchanged" "$(cksum <"$ORIGINAL")" "$(cksum <"$BF")"
assert_eq "6.4 unwritable prefix: no stamp written" no "$([ -f "$STAMP" ] && echo yes || echo no)"
assert_eq "6.5 unwritable prefix: silent" "" "$out"
mv "$BF" "$BF.off"
out="$(sync_run refresh 2>&1)"
assert_eq "6.6 missing Brewfile: exit 0" 0 "$?"
assert_eq "6.7 missing Brewfile: brew not called" 0 "$(calls)"
assert_eq "6.8 missing Brewfile: silent" "" "$out"
mv "$BF.off" "$BF"
out="$(HOME="$H" HOMEBREW_PREFIX="$PREFIX" PATH="/usr/bin:/bin" "$BASH" "$BREW_SYNC" refresh 2>&1)"
assert_eq "6.9 no brew on PATH: exit 0" 0 "$?"
assert_eq "6.10 no brew on PATH: silent (a shell start must not print)" "" "$out"

echo "--- 6c. refresh reports a failure once and still exits 0"
write_brewfile
rm -f "$CALLS" "$STAMP"
printf 'brew "newtool"\n' >"$DUMP"
chmod 444 "$BF"
if [ -w "$BF" ]; then
	echo "  SKIP  6c (this user ignores file modes)"
else
	out="$(sync_run refresh 2>&1)"
	assert_eq "6c.1 a failed refresh exits 0 (a shell start must not fail)" 0 "$?"
	assert_eq "6c.2 a failed refresh says so" 1 "$(printf '%s' "$out" | grep -c 'Brewfile refresh failed')"
	assert_eq "6c.3 the stamp was written, so the next try waits a day" yes "$([ -f "$STAMP" ] && echo yes || echo no)"
fi
chmod 644 "$BF"

echo "--- 6b. the other verbs"
rm -f "$CALLS"
sync_run install >/dev/null 2>&1
sync_run check >/dev/null 2>&1
assert_eq "6b.1 install and check reach brew with the HOME Brewfile" "install|check" "$(paste -sd'|' "$CALLS")"
out="$(sync_run bogus 2>&1)"
assert_eq "6b.2 an unknown verb exits 1" 1 "$?"
assert_eq "6b.3 the usage line lists refresh" "Usage: brew-sync.sh <install|check|dump|refresh>" "$out"
out="$(HOME="$H" PATH="/usr/bin:/bin" "$BASH" "$BREW_SYNC" dump 2>&1)"
assert_eq "6b.4 dump without brew exits 0" 0 "$?"
assert_eq "6b.5 dump without brew says so" "brew not found -- install Homebrew first: https://brew.sh" "$out"

echo "--- 7. shared.bash no longer overwrites the Brewfile"
assert_eq "7.1 shared.bash has no brew bundle dump" 0 "$(grep -c 'brew bundle dump' "$SHARED_BASH" || true)"
assert_eq "7.2 shared.bash has no --force" 0 "$(grep -c -e '--force' "$SHARED_BASH" || true)"
# Comment lines name the script too, so count only code lines. The "&)" is the background call.
assert_eq "7.3 shared.bash calls brew-sync.sh refresh once, in the background" 1 \
	"$(grep -v '^[[:space:]]*#' "$SHARED_BASH" | grep -c 'brew-sync\.sh" refresh &)' || true)"
assert_eq "7.4 brew-sync.sh has no --force" 0 "$(grep -c -e '--force' "$BREW_SYNC" || true)"

echo "--- 8. the real Brewfile is untouched"
assert_eq "8.1 checksum of $REPO_DIR/Brewfile is unchanged" "$REAL_BREWFILE_SUM" "$(cksum <"$REPO_DIR/Brewfile")"

if [ -n "${COV:-}" ]; then
	cov_end
	cov_report "$BREW_SYNC"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
