#!/usr/bin/env bash
# tests/test-no-rtk.sh -- rtk must not exist anywhere in the tracked repo except one Brewfile line.
#
# Why: rtk was measured and removed (2026-10-28). Its hook rewrote commands, 4,208 filter parses failed,
# and a median session saved about 3% of its tokens. A stray reference would bring back a rewrite hook,
# a dangling import, or a rule that tells Claude to use a tool that is not wired. The package stays in
# the Brewfile, so a new machine still installs it for use in other repos.
#
# Usage: bash tests/test-no-rtk.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

assert() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' \
			"$name" "${expected:-<none>}" "${actual:-<none>}"
		FAIL=$((FAIL + 1))
	fi
}

# tracked_hits <pathspec...>: tracked files whose text mentions rtk, one per line.
tracked_hits() {
	local f
	while IFS= read -r -d '' f; do
		[ "$f" = tests/test-no-rtk.sh ] && continue
		grep -Iiq rtk "$REPO_DIR/$f" && printf '%s\n' "$f"
	done < <(git -C "$REPO_DIR" ls-files -z -- "$@")
}

# json_hits <file>: number of strings in a JSON file that mention rtk.
json_hits() {
	jq '[.. | strings | select(test("rtk"; "i"))] | length' "$1"
}

# ── 0. The detectors catch what they guard (fail-to-fail) ──────────────────
echo "# 0. Detectors fail on a tree that still has rtk"
FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT
printf 'imports\n@RTK.md\n' >"$FIX/CLAUDE.md"
printf 'clean\n' >"$FIX/clean.md"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"rtk hook claude"}]}]}}\n' >"$FIX/settings.json"
printf '{"hooks":{}}\n' >"$FIX/clean.json"
grep -Iiq rtk "$FIX/CLAUDE.md"
assert "0.1 text detector flags an @RTK.md import" 0 $?
grep -Iiq rtk "$FIX/clean.md"
assert "0.2 text detector passes a clean file" 1 $?
assert "0.3 json detector flags an rtk hook" 1 "$(json_hits "$FIX/settings.json")"
assert "0.4 json detector passes a clean file" 0 "$(json_hits "$FIX/clean.json")"

# ── 1. Wiring ──────────────────────────────────────────────────────────────
echo "# 1. Wiring"
assert "1.1 no tracked path names rtk" "" "$(git -C "$REPO_DIR" ls-files | grep -i rtk)"
assert "1.2 settings.json holds no rtk string" 0 "$(json_hits "$REPO_DIR/claude/settings.json")"
assert "1.3 install.sh does not mention rtk" "" "$(tracked_hits install.sh)"
assert "1.4 CLAUDE.md does not mention rtk" "" "$(tracked_hits claude/CLAUDE.md)"
assert "1.5 Brewfile keeps exactly one brew rtk line" 1 "$(grep -c '^brew "rtk"$' "$REPO_DIR/Brewfile")"

printf '\ntest-no-rtk: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
