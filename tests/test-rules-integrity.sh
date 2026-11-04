#!/usr/bin/env bash
# tests/test-rules-integrity.sh, verification harness for the rules system
# (claude/rules/*.md <-> settings.json <-> rules-doctor.sh).
#
# Why: Claude Code loads every file in ~/.claude/rules/ by itself, and no CLAUDE.md index exists
# (decision D-003). A rule file without a description, a cross-reference to a rule that does not
# exist, or an em dash in a script would go unseen. The doctor must name each fault.
#
# Self-testing: run the doctor on a green tree, then apply every drift
# mutation at once and confirm the doctor names each targeted check. One
# multi-fault run rather than one run per fault: the doctor runs every check
# and never exits early, so each name assertion pins its own check (deleting
# check X removes the "X" line from the output), and a single exit-code
# assertion covers the shared FAIL plumbing. The per-fault exit-code
# assertions this replaced could not fail independently of the name
# assertions (tasks/trim-candidates.md, 2026-09-07).
#
# Hermetic: the doctor runs against a throwaway git repo that holds copies of claude/, install.sh,
# bash/, and .github/ (RULES_DOCTOR_REPO_DIR). The real claude/rules/ and claude/settings.json (live
# through the ~/.claude symlink) are never touched, so a concurrent Claude Code session cannot
# observe a mutated settings file mid-test. The fixture is a git repo because check F lists the
# tracked shell scripts with git ls-files.
#
# Usage: bash tests/test-rules-integrity.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_DIR/claude/scripts/rules-doctor.sh"
EMDASH="$(printf '\xe2\x80\x94')"

PASS=0
FAIL=0

assert() {
	local name="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' \
			"$name" "$expected" "$actual"
		FAIL=$((FAIL + 1))
	fi
}

assert_contains() {
	local name="$1" needle="$2" haystack="$3"
	if printf '%s' "$haystack" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected to contain: %s\n' "$name" "$needle"
		FAIL=$((FAIL + 1))
	fi
}

# ── Fixture: throwaway git repo with copies of the files the doctor reads ──
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# make_fixture <dir>: copy the tracked inputs of the doctor into <dir> and index them.
# -P keeps claude/skills' symlinks as symlinks instead of copying targets.
make_fixture() {
	mkdir -p "$1"
	cp -RP "$REPO_DIR/claude" "$1/claude"
	cp -RP "$REPO_DIR/bash" "$1/bash"
	cp -RP "$REPO_DIR/.github" "$1/.github"
	cp -P "$REPO_DIR/install.sh" "$1/install.sh"
	git init -q --template= "$1"
	git -C "$1" add claude bash .github install.sh
}

TMP_REPO="$WORK/repo"
make_fixture "$TMP_REPO"
SETTINGS="$TMP_REPO/claude/settings.json"
BEHAV_MD="$TMP_REPO/claude/rules/behavioral.md"

run_doctor() {
	RULES_DOCTOR_REPO_DIR="$TMP_REPO" bash "$DOCTOR" >"$1" 2>&1
}

# ── 1. Doctor passes on green tree, and the context rule file is in place ──
echo "# 1. Doctor on green tree"
run_doctor "$WORK/green.out"
assert "1.1 doctor exits 0 on the green tree" "0" "$?"
# D-003: a CLAUDE.md below claude/ hid the root AGENTS.md from sessions that start under claude/.
assert "1.2 no tracked path ends in CLAUDE.md" 0 "$(git -C "$REPO_DIR" ls-files | grep -c 'CLAUDE\.md$')"
assert "1.3 context.md is tracked" "claude/rules/context.md" \
	"$(git -C "$REPO_DIR" ls-files claude/rules/context.md)"
assert "1.4 context.md has a description line in its front matter" 1 \
	"$(sed -n '2,6p' "$REPO_DIR/claude/rules/context.md" | grep -c '^description: .')"
assert "1.5 tools.md tells Claude to check AGENTS.md files" 1 \
	"$(grep -c '^- Check for project and subdirectory AGENTS\.md files before starting work\.$' "$REPO_DIR/claude/rules/tools.md")"
# The context rule sends machine-local Claude instructions to claude/rules/<name>.local.md.
git -C "$REPO_DIR" check-ignore -q claude/rules/x.local.md
assert "1.6 .gitignore ignores a machine-local rule file" 0 "$?"
git -C "$REPO_DIR" check-ignore -q claude/rules/context.md
assert "1.7 .gitignore does not ignore a shared rule file" 1 "$?"

# ── 2. Every drift mutation at once ───────────────────────────────────────
echo "# 2. Every drift mutation applied at once"
RULES="$TMP_REPO/claude/rules"
# A.1: a rule file loses its description, one has no front matter, one has an empty description,
# one has a description but never closes its front matter
sed '/^description:/d' "$RULES/tools.md" >"$RULES/tools.md.tmp" && mv "$RULES/tools.md.tmp" "$RULES/tools.md"
printf '# Plain\n\nNo front matter here.\n' >"$RULES/no-front-matter.md"
printf -- '---\nname: blank\ndescription:   \n---\n\n# Blank\n' >"$RULES/blank-description.md"
printf -- '---\nname: open\ndescription: has text but no closing delimiter\n\n# Open\n' >"$RULES/unclosed-front-matter.md"
# A.2: a rule file that names a rules file which does not exist
printf '\nSee also: `rules/nonexistent-rule.md`.\n' >>"$RULES/git.md"
# C.3: behavioral.md loses its numbered H2 imperatives
sed '/^## [0-9]*\. /d' "$BEHAV_MD" >"${BEHAV_MD}.tmp" && mv "${BEHAV_MD}.tmp" "$BEHAV_MD"
# F.1: an em dash in a rule file, a hook script, install.sh, a bash file, and the workflow file
printf '\nA %s B\n' "$EMDASH" >>"$RULES/code-style.md"
printf '\n# A %s B\n' "$EMDASH" >>"$TMP_REPO/claude/hooks/block-em-dash.sh"
printf '\n# A %s B\n' "$EMDASH" >>"$TMP_REPO/install.sh"
printf '\n# A %s B\n' "$EMDASH" >>"$TMP_REPO/bash/shared.bash"
printf '\n# A %s B\n' "$EMDASH" >>"$TMP_REPO/.github/workflows/tests.yml"
HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then
	HAVE_JQ=1
	# D.1: a re-injection hook registered on UserPromptSubmit
	# E.1: a registered hook whose file does not exist
	# H.1: a secrets deny rule dropped from permissions.deny
	jq '.hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/surface-behavioral-rules.sh"}]}]
		| .hooks.Stop += [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/no-such-hook.sh"}]}]
		| .permissions.deny -= ["Read(**/.ssh/**)"]' \
		"$SETTINGS" >"$WORK/settings.json" && mv "$WORK/settings.json" "$SETTINGS"
fi
run_doctor "$WORK/faults.out"
RC=$?
OUT=$(cat "$WORK/faults.out")
assert "2.1 doctor exits non-zero with every fault present" "1" "$RC"
assert_contains "2.2 doctor names the rule file that lost its description (A.1)" "no description: tools.md" "$OUT"
assert_contains "2.3 doctor names the rule file with no front matter (A.1)" "no description: no-front-matter.md" "$OUT"
assert_contains "2.4 doctor names the rule file with an empty description (A.1)" "no description: blank-description.md" "$OUT"
assert_contains "2.4b doctor names the rule file with unclosed front matter (A.1)" "no description: unclosed-front-matter.md" "$OUT"
assert_contains "2.5 doctor names the cross-reference check (A.2)" "A.2 cross-reference resolves" "$OUT"
assert_contains "2.6 doctor names the file and the missing rules file (A.2)" "git.md references missing rules/nonexistent-rule.md" "$OUT"
assert_contains "2.7 doctor reports the imperative count (C.3)" "C.3 H2 imperatives" "$OUT"
assert_contains "2.8 doctor names the rule file with an em dash (F.1)" "U+2014 found in claude/rules/code-style.md" "$OUT"
assert_contains "2.9 doctor names the hook script with an em dash (F.1)" "U+2014 found in claude/hooks/block-em-dash.sh" "$OUT"
assert_contains "2.10 doctor names install.sh with an em dash (F.1)" "U+2014 found in install.sh" "$OUT"
assert_contains "2.11 doctor names the bash file with an em dash (F.1)" "U+2014 found in bash/shared.bash" "$OUT"
assert_contains "2.12 doctor names the workflow file with an em dash (F.1)" "U+2014 found in .github/workflows/tests.yml" "$OUT"
if [ "$HAVE_JQ" -eq 1 ]; then
	assert_contains "2.13 doctor reports re-injection (D.1)" "D.1 re-injection" "$OUT"
	assert_contains "2.14 doctor names the missing hook (E.1)" "no-such-hook.sh" "$OUT"
	assert_contains "2.15 doctor names the dropped deny rule (H.1)" "Read(**/.ssh/**)" "$OUT"
else
	echo "  SKIP  2.13-2.15 jq not available"
fi

# ── 3. A dangling behavioral.md rule reference (C.4) ──────────────────────
# Seeded on its own fresh copy: section 2 deletes every numbered heading, which would fail C.4 for
# the wrong reason. A reference to a rule that does not exist goes stale silently when rules are renumbered.
echo "# 3. Dangling behavioral.md rule reference"
REPO3="$WORK/repo3"
make_fixture "$REPO3"
printf '\nSee also: `rules/behavioral.md` rule 99 (does not exist).\n' >>"$REPO3/claude/rules/git.md"
RULES_DOCTOR_REPO_DIR="$REPO3" bash "$DOCTOR" >"$WORK/dangling.out" 2>&1
assert "3.1 doctor exits non-zero on a dangling rule reference" "1" "$?"
OUT3=$(cat "$WORK/dangling.out")
assert_contains "3.2 doctor names the check (C.4)" "C.4 behavioral.md rule references" "$OUT3"
assert_contains "3.3 doctor names the file and the missing rule" "git.md:rule-99" "$OUT3"

# ── 4. A tree with no tracked files cannot pass check F by default ────────
# Fail loud: an empty file list would let F pass without scanning anything.
echo "# 4. Check F fails loud outside a git work tree"
REPO4="$WORK/repo4"
mkdir -p "$REPO4"
cp -RP "$REPO_DIR/claude" "$REPO4/claude"
# The ceiling stops git from finding a repo in a parent folder of the fixture.
GIT_CEILING_DIRECTORIES="$WORK" RULES_DOCTOR_REPO_DIR="$REPO4" bash "$DOCTOR" >"$WORK/nogit.out" 2>&1
assert "4.1 doctor exits non-zero when it cannot list tracked files" "1" "$?"
assert_contains "4.2 doctor names the prerequisite failure (F.*)" "F.* prerequisites" "$(cat "$WORK/nogit.out")"

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "test-rules-integrity: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
