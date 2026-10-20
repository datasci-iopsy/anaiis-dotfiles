#!/usr/bin/env bash
# Let every admin profile on this Mac manage the shared Homebrew prefix.
#
# Adds one inheritable ACL entry for group "admin" to the prefix. Files that
# any admin profile creates later (kegs, taps, git objects, npm globals) inherit
# the entry, so the other profiles can upgrade or remove them without a chown.
# Homebrew gains no rights: it keeps running as the profile that invokes it,
# and non-admin users gain nothing.
#
# Idempotent. Re-run with sudo to repair paths created outside the ACL.
#
# Usage: sudo bash brew-share.sh [prefix]   (default: /opt/homebrew)
set -euo pipefail

PREFIX="${1:-/opt/homebrew}"
ENTRY="group:admin allow read,write,append,delete,execute,list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit"

if [ ! -d "$PREFIX" ]; then
	echo "prefix not found: $PREFIX" >&2
	exit 1
fi

# Strip inherited copies first so a re-run does not stack duplicate entries
# (chmod complains about paths with no ACL; that is the normal first-run
# state). Then give every existing path one explicit entry. New paths inherit
# from their parent directory.
chmod -R -I "$PREFIX" 2>/dev/null || true
rc=0
chmod -R +a "$ENTRY" "$PREFIX" || rc=$?

if [ "$rc" -ne 0 ]; then
	if [ "$(id -u)" -ne 0 ]; then
		echo "Some paths belong to other profiles. Re-run: sudo bash $0 $PREFIX" >&2
	fi
	exit "$rc"
fi
echo "Shared admin ACL applied to $PREFIX"
