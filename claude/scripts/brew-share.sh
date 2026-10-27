#!/usr/bin/env bash
# Let every admin profile on this Mac manage the shared Homebrew prefix.
#
# Adds two inheritable ACL entries for group "admin" to the prefix: one for
# directories and one for files. Paths that any admin profile creates later
# (kegs, taps, git objects, npm globals) inherit them, so the other profiles
# can upgrade or remove them without a chown. Homebrew gains no rights: it
# keeps running as the profile that invokes it, and non-admin users gain
# nothing.
#
# The file entry must not grant "execute". On a file, access(2) honors ACLs, so
# a file that carries "execute" reports as executable even with no x mode bit.
# Homebrew's cask installer tests that and skips its own chmod +x, which left
# the claude binary at mode 644 after every upgrade. "execute" and "search" are
# one permission bit, so only the directory entry carries it.
#
# Idempotent. Re-run with sudo to repair paths created outside the ACL, and to
# migrate the single entry that earlier versions of this script applied.
#
# Usage: sudo bash brew-share.sh [prefix]   (default: /opt/homebrew)
set -euo pipefail

PREFIX="${1:-/opt/homebrew}"
COMMON="read,write,append,delete,readattr,writeattr,readextattr,writeextattr,readsecurity"
FILE_ENTRY="group:admin allow ${COMMON},file_inherit,directory_inherit"
DIR_ENTRY="group:admin allow list,search,add_file,add_subdirectory,delete_child,directory_inherit"
# The one entry that earlier versions applied to files and directories alike.
LEGACY_ENTRY="group:admin allow ${COMMON},execute,list,search,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit"

if [ ! -d "$PREFIX" ]; then
	echo "prefix not found: $PREFIX" >&2
	exit 1
fi

# Only files and directories take an ACL. chmod -R follows symlinks and fails
# on a broken one (brew doctor lists those; brew cleanup removes them), so
# feed it the paths through find instead.
apply() {
	find "$PREFIX" \( -type f -o -type d \) -exec chmod "$@" {} +
}
apply_dirs() {
	find "$PREFIX" -type d -exec chmod "$@" {} +
}

# Strip inherited copies and every entry this script has ever applied, so a
# re-run does not stack duplicates and a migration drops the legacy entry
# (chmod complains about paths that lack an entry; that is the normal state).
# Then give every existing path its explicit entries. New paths inherit from
# their parent directory.
apply -I 2>/dev/null || true
for entry in "$LEGACY_ENTRY" "$DIR_ENTRY" "$FILE_ENTRY"; do
	apply -a "$entry" 2>/dev/null || true
done
rc=0
apply_dirs +a "$DIR_ENTRY" || rc=$?
apply +a "$FILE_ENTRY" || rc=$?

if [ "$rc" -ne 0 ]; then
	if [ "$(id -u)" -ne 0 ]; then
		echo "Some paths belong to other profiles. Re-run: sudo bash $0 $PREFIX" >&2
	fi
	exit "$rc"
fi

# Verify inheritance: a file created in the prefix must not inherit "execute".
# Read the ACL text; under sudo a -x test would pass for root whatever the ACL says.
probe="$(mktemp "$PREFIX/.brew-share-probe.XXXXXX")"
acl="$(ls -le "$probe")"
rm -f "$probe"
if grep -q 'allow.*execute' <<<"$acl"; then
	echo "New files in $PREFIX still inherit an execute grant:" >&2
	echo "$acl" >&2
	exit 1
fi
echo "Shared admin ACL applied to $PREFIX"
