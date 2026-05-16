#!/usr/bin/env bash
# UserPromptSubmit hook: advisory listing merged claude/* branches.
# Runs at most once per calendar day (flag file in /tmp).
# Never deletes branches. Output is advisory only.

FLAG="/tmp/claude-branch-hygiene-$(date +%Y%m%d)"
[ -f "$FLAG" ] && exit 0

MERGED=$(git branch --merged main 2>/dev/null \
	| grep -E '^\s*claude/' \
	| sed 's/^[[:space:]]*//')

if [ -z "$MERGED" ]; then
	touch "$FLAG"
	exit 0
fi

echo "[branch-hygiene] Merged claude/* branches you may want to delete:"
while IFS= read -r br; do
	echo "  $br"
done <<<"$MERGED"
echo "Run: git branch -d $(printf '%s ' $MERGED)"

touch "$FLAG"
exit 0
