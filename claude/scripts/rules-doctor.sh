#!/usr/bin/env bash
# rules-doctor.sh, verify the rules system against its intention, not its
# implementation. Rules load natively from ~/.claude/rules/ (symlinked to
# claude/rules/ in this repo); there is no injection pipeline.
#
# Exits 0 if all checks pass, 1 otherwise. Output is structured so the
# script is grep-able from a higher-level test harness.
#
# Checks:
#   A. Rule file integrity: every claude/rules/*.md file has a non-empty
#      description: line in its front matter, and every rules/<name>.md named
#      inside any rules file exists on disk. No CLAUDE.md index exists
#      (decision D-003); Claude Code loads each rules file by itself. Former
#      check B (cross-references) is now A.2; its letter stays unused so the
#      other check ids keep their meaning.
#   C. behavioral.md structure: H1 title and at least 9 numbered H2
#      imperatives.
#   D. No re-injection: no UserPromptSubmit hook in settings.json references
#      behavioral rules (native loading makes injection a duplicate).
#   E. Hook registration integrity: every $HOME/.claude/hooks/<name>.sh
#      command in settings.json resolves to an existing file in claude/hooks/.
#   F. No em dash (U+2014) in any tracked shell script (install.sh included),
#      any rules file, or the workflow file. The tracked list comes from git.
#   G. Deterministic language: no banned vague qualifiers in rules files.
#      A rule must state its threshold, not defer to judgment.
#   H. Secrets denial: settings.json denies the protected Read/Write paths
#      and does not auto-approve Bash(cat:*), which would bypass them.
#
# Usage: bash ~/.claude/scripts/rules-doctor.sh

set -u

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
# RULES_DOCTOR_REPO_DIR is a test-only override (same precedent as
# MEMORY_DOCTOR_REPO_DIR): tests point the doctor at a throwaway copy of
# claude/ so drift fixtures never touch the real rules/ or the live
# settings.json behind ~/.claude/settings.json. Unset in normal use.
REPO_DIR="${RULES_DOCTOR_REPO_DIR:-$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)}"
RULES_DIR="$REPO_DIR/claude/rules"
BEHAV_MD="$RULES_DIR/behavioral.md"
SETTINGS="$REPO_DIR/claude/settings.json"

PASS=0
FAIL=0

ok() {
	printf '  PASS  %s\n' "$1"
	PASS=$((PASS + 1))
}
fail() {
	printf '  FAIL  %s\n        %s\n' "$1" "$2"
	FAIL=$((FAIL + 1))
}

# has_description <file>: true when the front matter (the lines between the first
# "---" and the next "---") holds a description: line with text after the colon.
has_description() {
	awk '
		NR == 1 { if ($0 != "---") exit; fm = 1; next }
		fm && /^---[[:space:]]*$/ { exit }
		fm && /^description:[[:space:]]*[^[:space:]]/ { found = 1 }
		END { exit !found }
	' "$1"
}

# ── A. Rule file integrity ─────────────────────────────────────────────────
echo "## A. Rule file integrity"
if [ -d "$RULES_DIR" ]; then
	NO_DESC=0
	for f in "$RULES_DIR"/*.md; do
		if ! has_description "$f"; then
			NO_DESC=$((NO_DESC + 1))
			fail "A.1 rule file has a description" "no description: $(basename "$f")"
		fi
	done
	if [ "$NO_DESC" -eq 0 ]; then
		ok "A.1 every rules file has a description in its front matter"
	fi

	XREF_BAD=0
	for f in "$RULES_DIR"/*.md; do
		while IFS= read -r ref; do
			if [ ! -f "$REPO_DIR/claude/$ref" ]; then
				XREF_BAD=$((XREF_BAD + 1))
				fail "A.2 cross-reference resolves" "$(basename "$f") references missing $ref"
			fi
		done < <(grep -oE 'rules/[a-z0-9_-]+\.md' "$f" | sort -u)
	done
	if [ "$XREF_BAD" -eq 0 ]; then
		ok "A.2 every rules/<name>.md referenced inside rules files exists"
	fi
else
	fail "A.* prerequisites" "missing rules/ directory"
fi

# ── C. behavioral.md structure ─────────────────────────────────────────────
echo "## C. rules/behavioral.md"
if [ -f "$BEHAV_MD" ]; then
	ok "C.1 rules/behavioral.md exists"
	FIRST_CONTENT=$(awk '
		NR==1 && /^---$/  { fm=1; next }
		fm && /^---$/     { fm=0; next }
		fm                { next }
		/^[[:space:]]*$/  { next }
		                  { print; exit }
	' "$BEHAV_MD")
	if printf '%s' "$FIRST_CONTENT" | grep -qE '^# '; then
		ok "C.2 has H1 title"
	else
		fail "C.2 H1 title" "first non-frontmatter line is not '# Title'"
	fi
	H2_CT=$(grep -cE '^## [0-9]+\.' "$BEHAV_MD" || true)
	if [ "${H2_CT:-0}" -ge 8 ]; then
		ok "C.3 has $H2_CT numbered H2 imperatives (>= 8)"
	else
		fail "C.3 H2 imperatives" "expected at least 8, found ${H2_CT:-0}"
	fi
	# C.4: a "behavioral.md rule N" reference must name a rule that exists; renumbering strands them silently.
	BAD_RULE_REFS=""
	for f in "$RULES_DIR"/*.md; do
		[ -f "$f" ] || continue
		while IFS= read -r n; do
			[ "$n" -le "${H2_CT:-0}" ] || BAD_RULE_REFS="$BAD_RULE_REFS $(basename "$f"):rule-$n"
		done < <(grep -oE 'behavioral\.md`? rule [0-9]+' "$f" | grep -oE '[0-9]+$')
	done
	if [ -z "$BAD_RULE_REFS" ]; then
		ok "C.4 every behavioral.md rule reference points at an existing rule (1 to ${H2_CT:-0})"
	else
		fail "C.4 behavioral.md rule references" "no such rule:$BAD_RULE_REFS"
	fi
else
	fail "C.1 rules/behavioral.md" "missing: $BEHAV_MD"
fi

# ── D. No re-injection of natively loaded rules ────────────────────────────
echo "## D. No re-injection"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
	REINJECT=$(jq -r '.hooks.UserPromptSubmit[]?.hooks[]?.command // empty' "$SETTINGS" \
		| grep -ci 'behavioral' || true)
	if [ "${REINJECT:-0}" -eq 0 ]; then
		ok "D.1 no UserPromptSubmit hook re-injects behavioral rules"
	else
		fail "D.1 re-injection" "$REINJECT UserPromptSubmit command(s) reference behavioral rules; rules load natively"
	fi
else
	fail "D.* prerequisites" "jq missing or settings.json absent"
fi

# ── E. Hook registration integrity ─────────────────────────────────────────
echo "## E. Hook registration integrity"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
	STALE=0
	while IFS= read -r hookpath; do
		relname="${hookpath#\$HOME/.claude/hooks/}"
		if [ ! -f "$REPO_DIR/claude/hooks/$relname" ]; then
			STALE=$((STALE + 1))
			fail "E.1 registered hook exists" "settings.json registers missing claude/hooks/$relname"
		fi
	done < <(jq -r '.hooks | .. | .command? // empty' "$SETTINGS" \
		| grep -oE '\$HOME/\.claude/hooks/[A-Za-z0-9_.-]+\.sh' | sort -u)
	if [ "$STALE" -eq 0 ]; then
		ok "E.1 every hook registered in settings.json exists in claude/hooks/"
	fi
else
	fail "E.* prerequisites" "jq missing or settings.json absent"
fi

# ── F. No em dash in shell scripts, rules files, or the workflow file ───────
echo "## F. Em dash ban"
EMDASH=$(printf '\xe2\x80\x94')
EM_BAD=0
# em_check <path relative to the repo>: fail when the file holds U+2014.
em_check() {
	if grep -qF "$EMDASH" "$REPO_DIR/$1" 2>/dev/null; then
		EM_BAD=$((EM_BAD + 1))
		fail "F.1 no em dash" "U+2014 found in $1"
	fi
}
# An empty list means git could not list the tree. Fail loud: F must not pass without a scan.
EM_TRACKED=$(git -C "$REPO_DIR" ls-files -- '*.sh' '*.bash' .github/workflows/tests.yml 2>/dev/null)
if [ -z "$EM_TRACKED" ]; then
	fail "F.* prerequisites" "git ls-files lists no shell scripts in $REPO_DIR (not a git work tree?)"
else
	while IFS= read -r rel; do
		em_check "$rel"
	done <<EOF
$EM_TRACKED
EOF
fi
for f in "$RULES_DIR"/*.md; do
	em_check "claude/rules/$(basename "$f")"
done
if [ "$EM_BAD" -eq 0 ] && [ -n "$EM_TRACKED" ]; then
	ok "F.1 no em dash in any tracked shell script, rules file, or the workflow file"
fi

# ── G. Deterministic language: no vague qualifiers ─────────────────────────
echo "## G. Deterministic language"
VAGUE_TERMS='when appropriate|as needed|if necessary|where possible|use sparingly|judiciously'
VAGUE_BAD=0
for f in "$RULES_DIR"/*.md; do
	HITS=$(grep -ciE "$VAGUE_TERMS" "$f" || true)
	if [ "${HITS:-0}" -gt 0 ]; then
		VAGUE_BAD=$((VAGUE_BAD + 1))
		fail "G.1 no vague qualifiers" "$(basename "$f") has $HITS banned phrase(s); state the threshold instead"
	fi
done
if [ "$VAGUE_BAD" -eq 0 ]; then
	ok "G.1 no banned vague qualifiers in rules files"
fi

# ── H. Secrets denial in settings.json ──────────────────────────────────────
echo "## H. Secrets denial"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
	REQUIRED_DENY=(
		'Read(**/*.key)'
		'Edit(**/*.key)'
		'Read(**/*.pem)'
		'Edit(**/*.pem)'
		'Read(**/*credentials*)'
		'Edit(**/*credentials*)'
		'Read(**/secrets/**)'
		'Edit(**/secrets/**)'
		'Read(**/.ssh/**)'
		'Edit(**/.ssh/**)'
		'Read(~/.bashrc)'
		'Edit(~/.bashrc)'
		'Read(~/.bashrc.local)'
		'Edit(~/.bashrc.local)'
		'Read(~/.bash_profile)'
		'Edit(~/.bash_profile)'
		'Read(~/.zshrc)'
		'Edit(~/.zshrc)'
		'Read(~/.zshrc.local)'
		'Edit(~/.zshrc.local)'
		'Read(~/.profile)'
		'Edit(~/.profile)'
		'Read(~/.aws/**)'
		'Edit(~/.aws/**)'
		'Read(~/.config/gcloud/**)'
		'Edit(~/.config/gcloud/**)'
		'Read(~/.config/secrets/**)'
		'Edit(~/.config/secrets/**)'
		'Read(~/.netrc)'
		'Edit(~/.netrc)'
		'Read(~/.gnupg/**)'
		'Edit(~/.gnupg/**)'
		'Read(~/.docker/**)'
		'Edit(~/.docker/**)'
		'Read(~/.kube/**)'
		'Edit(~/.kube/**)'
		'Read(~/.npmrc)'
		'Edit(~/.npmrc)'
		'Read(~/.pypirc)'
		'Edit(~/.pypirc)'
		'Read(~/.config/gh/**)'
		'Edit(~/.config/gh/**)'
	)
	DENY_MISSING=0
	for rule in "${REQUIRED_DENY[@]}"; do
		if ! jq -e --arg r "$rule" '.permissions.deny | index($r)' "$SETTINGS" >/dev/null 2>&1; then
			DENY_MISSING=$((DENY_MISSING + 1))
			fail "H.1 required deny rule present" "missing: $rule"
		fi
	done
	if [ "$DENY_MISSING" -eq 0 ]; then
		ok "H.1 all ${#REQUIRED_DENY[@]} secrets deny rules present"
	fi
	if jq -e '.permissions.allow | index("Bash(cat:*)")' "$SETTINGS" >/dev/null 2>&1; then
		fail "H.2 Bash(cat:*) not auto-approved" "Bash(cat:*) in allow list bypasses the Read deny rules"
	else
		ok "H.2 Bash(cat:*) is not auto-approved"
	fi
	# The .env family has no settings.json deny glob (no negation syntax exists
	# to carve out .env.example/.env.template from a wildcard), so protection
	# lives solely in block-sensitive-writes.sh; it must be wired to Read too,
	# not just Write/Edit, or Read of a real .env file goes unguarded.
	if jq -e '.hooks.PreToolUse[].hooks[] | select(.command | test("block-sensitive-writes"))' "$SETTINGS" >/dev/null 2>&1 \
		&& jq -e '.hooks.PreToolUse[] | select(.hooks[].command | test("block-sensitive-writes")) | .matcher | test("Read")' "$SETTINGS" >/dev/null 2>&1; then
		ok "H.3 block-sensitive-writes.sh matcher covers Read"
	else
		fail "H.3 block-sensitive-writes.sh matcher covers Read" "matcher missing Read; .env-family Read protection now lives only in this hook"
	fi
else
	fail "H.* prerequisites" "jq missing or settings.json absent"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "rules-doctor: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
