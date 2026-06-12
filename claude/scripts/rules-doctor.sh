#!/usr/bin/env bash
# rules-doctor.sh, verify the rules system against its intention, not its
# implementation. Rules load natively from ~/.claude/rules/ (symlinked to
# claude/rules/ in this repo); there is no injection pipeline.
#
# Exits 0 if all checks pass, 1 otherwise. Output is structured so the
# script is grep-able from a higher-level test harness.
#
# Checks:
#   A. Index integrity: every claude/rules/*.md file is listed in CLAUDE.md's
#      rules index, and every rules/<name>.md referenced in CLAUDE.md exists
#      on disk.
#   B. Cross-reference integrity: every rules/<name>.md referenced inside any
#      rules file exists on disk.
#   C. behavioral.md structure: H1 title and at least 9 numbered H2
#      imperatives.
#   D. No re-injection: no UserPromptSubmit hook in settings.json references
#      behavioral rules (native loading makes injection a duplicate).
#   E. Hook registration integrity: every $HOME/.claude/hooks/<name>.sh
#      command in settings.json resolves to an existing file in claude/hooks/.
#   F. No em dash (U+2014) in CLAUDE.md or any rules file.
#   G. Deterministic language: no banned vague qualifiers in rules files.
#      A rule must state its threshold, not defer to judgment.
#   H. Secrets denial: settings.json denies the protected Read/Write paths
#      and does not auto-approve Bash(cat:*), which would bypass them.
#
# Usage: bash ~/.claude/scripts/rules-doctor.sh

set -u

SCRIPT_REAL="$(realpath "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "$SCRIPT_REAL")/../.." && pwd)"
CLAUDE_MD="$REPO_DIR/claude/CLAUDE.md"
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

# ── A. Index integrity: rules/ on disk ↔ CLAUDE.md rules index ────────────
echo "## A. Index integrity"
if [ -f "$CLAUDE_MD" ] && [ -d "$RULES_DIR" ]; then
	UNLISTED=0
	for f in "$RULES_DIR"/*.md; do
		name="rules/$(basename "$f")"
		if ! grep -qF "$name" "$CLAUDE_MD"; then
			UNLISTED=$((UNLISTED + 1))
			fail "A.1 rules file listed in CLAUDE.md index" "not listed: $name"
		fi
	done
	if [ "$UNLISTED" -eq 0 ]; then
		ok "A.1 every rules file is listed in CLAUDE.md"
	fi

	DANGLING=0
	while IFS= read -r ref; do
		if [ ! -f "$REPO_DIR/claude/$ref" ]; then
			DANGLING=$((DANGLING + 1))
			fail "A.2 CLAUDE.md reference resolves" "missing on disk: $ref"
		fi
	done < <(grep -oE 'rules/[a-z0-9_-]+\.md' "$CLAUDE_MD" | sort -u)
	if [ "$DANGLING" -eq 0 ]; then
		ok "A.2 every rules/<name>.md referenced in CLAUDE.md exists"
	fi
else
	fail "A.* prerequisites" "missing CLAUDE.md or rules/ directory"
fi

# ── B. Cross-reference integrity inside rules files ────────────────────────
echo "## B. Cross-reference integrity"
XREF_BAD=0
for f in "$RULES_DIR"/*.md; do
	while IFS= read -r ref; do
		if [ ! -f "$REPO_DIR/claude/$ref" ]; then
			XREF_BAD=$((XREF_BAD + 1))
			fail "B.1 cross-reference resolves" "$(basename "$f") references missing $ref"
		fi
	done < <(grep -oE 'rules/[a-z0-9_-]+\.md' "$f" | sort -u)
done
if [ "$XREF_BAD" -eq 0 ]; then
	ok "B.1 every rules/<name>.md referenced inside rules files exists"
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
	if [ "${H2_CT:-0}" -ge 9 ]; then
		ok "C.3 has $H2_CT numbered H2 imperatives (>= 9)"
	else
		fail "C.3 H2 imperatives" "expected at least 9, found ${H2_CT:-0}"
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

# ── F. No em dash in CLAUDE.md or rules files ──────────────────────────────
echo "## F. Em dash ban"
EMDASH=$(printf '\xe2\x80\x94')
EM_BAD=0
for f in "$CLAUDE_MD" "$RULES_DIR"/*.md; do
	if grep -qF "$EMDASH" "$f" 2>/dev/null; then
		EM_BAD=$((EM_BAD + 1))
		fail "F.1 no em dash" "U+2014 found in $(basename "$f")"
	fi
done
if [ "$EM_BAD" -eq 0 ]; then
	ok "F.1 no em dash in CLAUDE.md or rules files"
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
		'Read(**/.env*)'
		'Write(**/.env*)'
		'Read(**/*.key)'
		'Read(**/*.pem)'
		'Read(**/*credentials*)'
		'Read(**/secrets/**)'
		'Read(**/.ssh/**)'
		'Write(**/.ssh/**)'
		'Read(~/.bashrc)'
		'Write(~/.bashrc)'
		'Read(~/.bashrc.local)'
		'Write(~/.bashrc.local)'
		'Read(~/.bash_profile)'
		'Write(~/.bash_profile)'
		'Read(~/.zshrc)'
		'Write(~/.zshrc)'
		'Read(~/.aws/**)'
		'Read(~/.config/gcloud/**)'
		'Read(~/.config/secrets/**)'
		'Write(~/.config/secrets/**)'
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
else
	fail "H.* prerequisites" "jq missing or settings.json absent"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "──────────────────────────────────────────────"
echo "rules-doctor: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
