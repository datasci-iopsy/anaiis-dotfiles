#!/usr/bin/env bash
# bash-guard.sh: single PreToolUse:Bash guard, merging the former
# block-destructive-commands.sh and prefer-jq.sh. One stdin read and one jq
# parse per Bash call instead of two of each.
#
# 1. Deny destructive bq, gcloud, and uv subcommands that need regex matching
#    beyond the settings.json deny list.
# 2. Deny commands referencing protected secrets paths (.env, .ssh, shell rc
#    files, secrets/ dirs, .pem/\w.key, credentials) and commands that dump the
#    environment (printenv/env bare, echo/printf of TOKEN/SECRET/KEY vars).
#    Read()/Write() deny rules cover the file tools; this closes the Bash
#    side. .env.example and .env.template stay usable.
# 3. Deny python/python3 when `import json` is the sole import: pure JSON
#    parsing is jq's job (pre-approved, streaming, faster). Scripts importing
#    anything else alongside json pass through.
#
# Input:  PreToolUse JSON on stdin.
# Output: stderr message + exit 2 to deny; exit 0 otherwise.
# Fails open when jq is missing.

set -u

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

[ -z "$CMD" ] && exit 0

# Append a line to the secret-access block log; best-effort, never blocks.
log_secret_block() {
	local surface="$1" detail="$2"
	local log_dir="$HOME/.claude/logs"
	local safe_session safe_detail
	safe_session=$(printf '%s' "${SESSION_ID:-unknown}" | tr -d '\n\r\t')
	safe_detail=$(printf '%s' "$detail" | tr -d '\n\r\t')
	mkdir -p "$log_dir" 2>/dev/null
	printf '%s\t%s\t%s\t%s\n' \
		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$safe_session" "$surface" "$safe_detail" \
		>>"$log_dir/secret-access-blocks.log" 2>/dev/null || true
}

# ── Destructive commands ────────────────────────────────────────────────────
if printf '%s' "$CMD" | grep -qE '^bq\s+rm\b'; then
	printf 'BLOCK: bq rm is destructive. Run this manually in terminal.\n' >&2
	exit 2
fi

if printf '%s' "$CMD" | grep -qE '^gcloud\s.*(delete|destroy|remove-iam-policy|set-iam-policy|disable|reset-windows-password)'; then
	printf 'BLOCK: Destructive gcloud command detected. Run this manually in terminal.\n' >&2
	exit 2
fi

if printf '%s' "$CMD" | grep -qE '^uv\s+(cache\s+(clean|prune)|publish|tool\s+uninstall|pip\s+uninstall)'; then
	printf 'BLOCK: Destructive uv command detected. Run this manually in terminal.\n' >&2
	exit 2
fi

# ── Force-push safety ────────────────────────────────────────────────────────
# Bare --force/-f (unsafe, no remote-side check) is always blocked, everywhere.
# --force-with-lease (safe, refuses to overwrite a remote ref with commits the
# local repo hasn't seen) is allowed. settings.json's deny-list glob matching
# can't express this distinction (substring matching, no negation --
# --force-with-lease always also matches a git push --force* deny), so this
# hook is the real enforcement point for the --force/--force-with-lease split,
# not settings.json.
if printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)git\s+push\b' \
	&& printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-f|--force)([[:space:]=]|$)'; then
	printf 'BLOCK: bare --force/-f push is unsafe (no remote-side check). Use --force-with-lease instead.\n' >&2
	exit 2
fi

# ── Secrets: token-minting commands ─────────────────────────────────────────
# These commands take no file path (so the protected-path check below never
# sees them) but their sole output is a live, usable credential.
if printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)gcloud\s+auth\s+print-(access|identity)-token\b' \
	|| printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)aws\s+sts\s+get-(session|federation)-token\b' \
	|| printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)heroku\s+auth:token\b' \
	|| printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)doctl\s+auth\s+token\b'; then
	log_secret_block "bash-guard:token-mint" "$CMD"
	printf 'BLOCK: command mints a live credential/token. Run this manually in terminal if genuinely needed.\n' >&2
	exit 2
fi

# ── Secrets: message-flag prose strip ───────────────────────────────────────
# Quoted arguments to message flags (-m, --message, --title, --body, --notes,
# --description) carry prose, not commands; commit messages must be able to
# name a file like .env without a block. Strip them before path matching,
# but only when they provably cannot execute or expand anything:
#   - single-quoted: always inert, always stripped
#   - "$(cat <<'DELIM' ... DELIM)" (single-quoted heredoc delimiter, the
#     project's own commit-message convention): also always inert -- a
#     single-quoted delimiter guarantees bash performs zero expansion on the
#     heredoc body, so it's as safe as a bare single-quoted string. Requires
#     the closing DELIM (optionally tab-indented, for <<-) to be immediately
#     followed by the closing )" with nothing else in between, so a real
#     command chained after the heredoc (; cat .env) is never swallowed.
#   - double-quoted: stripped only if free of $ and backtick (no expansion,
#     no command substitution); "$(cat .env)" therefore stays visible
# A message flag interpolating a secret-named variable is blocked outright:
# the shell would expand the real value into the message.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-m|--message|--title|--body|--notes|--description)(=|[[:space:]]+)("[^"]*\$\{?[A-Za-z0-9_]*(TOKEN|SECRET|API_?KEY|PASSWORD)|\$\{?[A-Za-z_][A-Za-z0-9_]*(TOKEN|SECRET|API_?KEY|PASSWORD))'; then
	printf 'BLOCK: message flag interpolates a secret-named variable; the expanded value would land in the message text.\n' >&2
	exit 2
fi

GUARD_STR="$CMD"
if command -v perl >/dev/null 2>&1; then
	GUARD_STR=$(printf '%s' "$CMD" | perl -0777 -pe '
		my $f = qr/(?:-m|--message|--title|--body|--notes|--description)/;
		s/((?:^|\s)$f(?:=|\s+))\x27[^\x27]*\x27/${1}\x27\x27/gs;
		s/((?:^|\s)$f(?:=|\s+))"\$\(\s*cat\s+<<-?\x27([A-Za-z_][A-Za-z0-9_]*)\x27\s*\n.*?\n[ \t]*\2\s*\)"/${1}""/gs;
		s/((?:^|\s)$f(?:=|\s+))"[^"`\$]*"/${1}""/gs;
	' 2>/dev/null) || GUARD_STR="$CMD"
	[ -n "$GUARD_STR" ] || GUARD_STR="$CMD"
fi

# ── Secrets: protected paths ────────────────────────────────────────────────
# Strip the allowed template forms first so they never trigger the path match.
# Also strip a jq filter's leading .env key reference (jq '.env', jq -r
# '.env.FOO') -- that operates on in-memory JSON already piped/passed to jq,
# never reads an actual .env file from disk, so it isn't a path reference at
# all. Only the occurrence immediately after a jq invocation is stripped; a
# real file argument elsewhere in the same command (cat .env | jq '.foo')
# still matches below. The trailing char class stands in for \b (word
# boundary) -- BSD sed's -E doesn't support \b, unlike this file's grep -E
# calls, which run through a GNU-compatible grep on this system.
SCRUBBED=$(printf '%s' "$GUARD_STR" | sed -E 's/\.env\.(example|template)//g' \
	| sed -E "s/(jq([[:space:]]+--?[A-Za-z][A-Za-z-]*)*[[:space:]]+)(['\"])\.env([^A-Za-z0-9_]|\$)/\1\3\4/g")
if printf '%s' "$SCRUBBED" | grep -qE '(\.env\b|\.ssh\b|\.bashrc(\.local)?|\.bash_profile|\.zshrc(\.local)?|\.profile\b|secrets/|\.pem\b|(^|[/[:space:]])\.?\w*\.key\b|credentials|\.aws\b|\.config/(gcloud|secrets|gh)\b|\.netrc\b|\.gnupg\b|\.docker/config|\.kube/config|\.npmrc\b|\.pypirc\b)'; then
	log_secret_block "bash-guard:protected-path" "$CMD"
	printf 'BLOCK: command references a protected secrets path. If a value is needed, ask the user to provide or load it.\n' >&2
	exit 2
fi

# ── Secrets: environment dumps ──────────────────────────────────────────────
if printf '%s' "$CMD" | grep -qE '^[[:space:]]*(printenv|env)[[:space:]]*($|\|)' \
	|| printf '%s' "$GUARD_STR" | grep -qE 'printenv[[:space:]]+.*(TOKEN|SECRET|API_?KEY|PASSWORD)' \
	|| printf '%s' "$GUARD_STR" | grep -qE '\b(echo|printf)\b[^|;&]*\$\{?[A-Za-z0-9_]*(TOKEN|SECRET|API_?KEY|PASSWORD)'; then
	log_secret_block "bash-guard:env-dump" "$CMD"
	printf 'BLOCK: command would print environment secrets. If a value is needed, ask the user to provide it.\n' >&2
	exit 2
fi

# ── Secrets: language-level environment dumps ───────────────────────────────
# Data-calibrated against tests/fixtures/env-dump/{malicious,benign}.txt (see
# calibrate.sh): blocks full/untargeted dumps (os.environ printed or dict()'d,
# .items()/.keys()/.values(), process.env printed bare, ENV.to_h/inspect) plus
# targeted getenv/index access when it co-occurs with a secret-shaped name
# (TOKEN/SECRET/API_?KEY/PASSWORD). Ordinary os.getenv('CONFIG_VAR', default)
# calls with no secret-shaped name pass through.
if printf '%s' "$CMD" | grep -qE '(os\.environ|process\.env)\)' \
	|| printf '%s' "$CMD" | grep -qE 'os\.environ\.(items|keys|values)\(\)' \
	|| printf '%s' "$CMD" | grep -qE '\bENV\.(to_h|inspect)\b' \
	|| { printf '%s' "$CMD" | grep -qE '(os\.getenv|os\.environ\[|process\.env\.|ENV\[)' \
		&& printf '%s' "$CMD" | grep -qiE '(TOKEN|SECRET|API_?KEY|PASSWORD)'; }; then
	log_secret_block "bash-guard:env-dump-lang" "$CMD"
	printf 'BLOCK: command would print language-level environment secrets (python/node/ruby). If a value is needed, ask the user to provide it.\n' >&2
	exit 2
fi

# ── Prefer jq over Python for pure JSON parsing ─────────────────────────────
# Only python/python3 commands whose sole import is json are blocked. A comma
# after json (import json, pandas) or any other import statement means the
# script does more than parsing; allow it.
if printf '%s' "$CMD" | grep -qE '\b(python|python3)\b' \
	&& printf '%s' "$CMD" | grep -qE '\bimport\s+json\b' \
	&& ! printf '%s' "$CMD" | grep -qE '\bimport\s+json\s*,' \
	&& ! printf '%s' "$CMD" | sed 's/import[[:space:]]*json//g' | grep -qE '\bimport\s+\w'; then
	echo "Prefer jq over Python for JSON parsing -- import json is the only import, this is a pure parsing task. jq is pre-approved, streaming, and faster." >&2
	exit 2
fi

# ── uv add/pip install: transparency notice ─────────────────────────────────
# uv is the sole sanctioned Python dependency tool (rules/python.md); these two
# subcommands are allowed, never blocked. This notice makes a dependency
# change visible in the transcript instead of silent, it never gates anything.
if printf '%s' "$CMD" | grep -qE '\buv\s+add\b'; then
	echo "[deps] $CMD -- modifies pyproject.toml/uv.lock" >&2
elif printf '%s' "$CMD" | grep -qE '\buv\s+pip\s+install\b'; then
	echo "[deps] $CMD -- installs into the active environment (pyproject.toml/uv.lock not updated)" >&2
fi

# ── Recursive rm: scoped allow/ask instead of a blanket settings.json deny ──
# settings.json's Bash(rm -r*)/Bash(rm -fr*)/Bash(rm -R*) denies blocked every
# recursive delete unconditionally, including disposable paths (a session
# scratchpad dir, .venv, node_modules, build artifacts, tests/fixtures/).
# This section replaces that blanket deny with a precise safe-list, reusing
# the traversal-safe technique from the tests/fixtures/ .env carve-out above
# (a path segment can't start with "." so ".." never matches). Runs LAST,
# after every other exit-2 check in this file, so an overlapping genuinely
# dangerous case (rm -rf ~/.ssh) still hits the existing hard block above,
# never gets downgraded to this section's ask.
#
# A hook's permissionDecision covers the WHOLE command, not per-subcommand
# (unlike settings.json rule matching), so this never emits "allow" for a
# compound command: rm -rf .venv && rm -rf /etc must not get laundered
# through an allow keyed off the first-looking operand.
#
# Detection is broadened (rm, /bin/rm, /usr/bin/rm, \rm; every recursive
# flag spelling; a bare word boundary rather than a strict subcommand-start
# anchor, since rm commonly follows a shell keyword like a for-loop's "do")
# because gate-evasion only ever degrades to this section's own "no
# opinion" (falling through to the harness's default ask-prompt), never to
# a silent allow: broadening can only reduce unnecessary prompts, never
# weaken safety. Checked against $GUARD_STR (already message-flag-scrubbed)
# so a commit message merely mentioning "rm" and a flag as prose can't
# spuriously trigger this section.
#
# Known residual risk, accepted (not fixed): the safe-list matches the
# operand STRING, not the resolved filesystem path. A symlink named like a
# safe entry (.venv, node_modules, ...) pointing elsewhere would match and
# silently allow. Requires an attacker to have already planted that symlink,
# a materially higher bar than a crafted command; closing it fully would
# need realpath/readlink -f resolution, a class of logic (real filesystem
# syscalls) this file doesn't otherwise use.
#
# Also known: this is word-splitting, not a shell parser, so a quoted-but-
# otherwise-safe operand (rm -rf ".venv") fails the character allowlist below
# and asks rather than allows -- same class of limitation as every other
# regex-based check in this file, documented rather than engineered around.
#
# Gate check runs against RM_SCAN_STR, not GUARD_STR: a further pass blanks
# any complete single- or double-quoted span whose CONTENT contains
# whitespace, so "rm -rf" appearing only as prose/test-data inside some
# other command's quoted argument (a log message, a nested bash -c script
# literal) never activates this section at all -- observed live: writing
# example commands in ledger rationale text, and a surgeon's own bash -c
# verification snippet, both tripped this section despite invoking no real
# rm. The whitespace requirement is deliberate, not incidental: a short,
# no-whitespace quoted span (like "rm" as a quoted command name, "rm" -rf /)
# is a real, executable invocation in bash and must stay visible, so it is
# never blanked -- only multi-word content is prose/data by construction.
# The tripwire and operand-safety logic below still run against the
# ORIGINAL $CMD once the section is entered, so a genuine quoted operand
# (rm -rf "$HOME") is unaffected; only the gate's activation decision
# ignores quoted spans, never the safety logic itself.
#
# Known limitation, same class as elsewhere in this file: this doesn't
# parse nested shell invocations, so bash -c "rm -rf /" or eval "rm -rf /"
# would have its whole payload blanked and fall through with no opinion.
# Every other check in this file has the identical blind spot (none parse
# into eval/bash -c/sh -c payloads), so this isn't a new gap, just the same
# accepted one extended to this section.
#
# Heredoc bodies (<<'EOF' ... EOF or <<EOF ... EOF) are also blanked before
# the gate check, for the same reason as quoted spans above: "rm -rf"
# appearing as literal text inside a heredoc (e.g. a test/log script written
# via `cat > file <<'EOF' ... EOF`) is data, not a command, and a heredoc
# body is never itself a command-name position (unlike a quoted string),
# so unlike the quote-blanking above, no whitespace check is needed here --
# the whole body is always safe to blank for gate-detection purposes.
# Observed live from an agent's own verification heredoc, and again from a
# PR body written via this same pattern, during this session.
#
# Known limitation, same class as the bash -c/eval case above: a heredoc
# piped directly to a shell (bash <<'EOF' ... EOF) would have its payload
# blanked too and fall through with no opinion -- this isn't a new gap,
# just the already-accepted "doesn't parse into shell-executed payloads"
# blind spot extended to this quoting mechanism.
RM_GATE_RE='\brm\b[^;&|]*((^|[[:space:]])-[A-Za-z]*[rR][A-Za-z]*\b|--recursive\b)'
RM_SCAN_STR="$GUARD_STR"
if command -v perl >/dev/null 2>&1; then
	RM_SCAN_STR=$(printf '%s' "$GUARD_STR" | perl -0777 -pe '
		s/<<-?(\x27?)([A-Za-z_][A-Za-z0-9_]*)\1[ \t]*\n.*?\n[ \t]*\2\b//gs;
		s/\x27([^\x27]*)\x27/$1 =~ m{\s} ? q() : $&/ges;
		s/"((?:\\.|[^"\\])*)"/$1 =~ m{\s} ? q() : $&/ges;
	' 2>/dev/null) || RM_SCAN_STR="$GUARD_STR"
fi
RM_GATE_SCAN_STR="${RM_SCAN_STR//$'\n'/ }"
if printf '%s' "$RM_GATE_SCAN_STR" | grep -qE "$RM_GATE_RE"; then
	# Tripwire scan runs FIRST, on the whole word list, before the compound-
	# operator check below and independent of it: a catastrophic operand
	# (notably $HOME and /* -- both contain a character, $ or *, that the
	# compound-operator check treats as a shell metacharacter) is exactly as
	# dangerous whether or not it's chained with other commands, so this
	# takes priority over everything else in this section, including ask.
	read -r -a RM_WORDS <<<"$CMD"
	for RM_I in "${!RM_WORDS[@]}"; do
		RM_W="${RM_WORDS[$RM_I]}"
		RM_W_LEN=${#RM_W}
		if ((RM_W_LEN >= 2)) && { [[ "${RM_W:0:1}" == '"' && "${RM_W: -1}" == '"' ]] || [[ "${RM_W:0:1}" == "'" && "${RM_W: -1}" == "'" ]]; }; then
			RM_W="${RM_W:1:RM_W_LEN-2}"
		fi
		case "$RM_W" in
			/ | '/*' | '~' | '$HOME' | . | ..)
				printf 'BLOCK: rm -rf targeting a catastrophic path (%s) is never automatic. Run manually in terminal if genuinely needed.\n' "$RM_W" >&2
				exit 2
				;;
		esac
	done

	if printf '%s' "$GUARD_STR" | grep -qE '[;&|`$()<>]' || [[ "$GUARD_STR" == *$'\n'* ]]; then
		jq -n --arg r "recursive rm alongside a shell operator/substitution -- cannot verify each path independently" \
			'{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": $r}}'
		exit 0
	fi

	RM_IDX=-1
	for RM_I in "${!RM_WORDS[@]}"; do
		case "${RM_WORDS[$RM_I]}" in
			rm | */rm | '\rm') RM_IDX=$RM_I ;;
		esac
	done

	RM_ASK_REASON=""
	if [ "$RM_IDX" -lt 0 ]; then
		RM_ASK_REASON="matched the recursive-rm pattern but could not precisely locate the rm invocation"
	else
		# Every remaining operand must be plain path text AND match
		# the safe-list, or the whole command asks (first failure wins,
		# named in the reason).
		RM_SEG='([^./][^/]*/)*[^./][^/]*'
		RM_ARTIFACTS='\.venv|node_modules|dist|build|\.next|coverage|__pycache__'
		RM_SAFE_SCRATCH="^(/private)?/tmp/claude-[0-9]+/${RM_SEG}/scratchpad(/${RM_SEG})?/?\$"
		RM_SAFE_ARTIFACT="^(\\./)?(${RM_SEG}/)?(${RM_ARTIFACTS})(/${RM_SEG})?/?\$"
		RM_SAFE_FIXTURE="^(\\./)?tests/fixtures/${RM_SEG}/?\$"

		RM_OPERAND_COUNT=0
		RM_SEEN_DASHDASH=0
		for ((RM_I = RM_IDX + 1; RM_I < ${#RM_WORDS[@]}; RM_I++)); do
			RM_W="${RM_WORDS[$RM_I]}"
			if [ "$RM_W" = "--" ]; then
				RM_SEEN_DASHDASH=1
				continue
			fi
			if [ "$RM_SEEN_DASHDASH" -eq 0 ]; then
				case "$RM_W" in -*) continue ;; esac
			fi
			RM_OPERAND_COUNT=$((RM_OPERAND_COUNT + 1))
			if ! printf '%s' "$RM_W" | grep -qE '^[A-Za-z0-9._/-]+$'; then
				RM_ASK_REASON="operand \"$RM_W\" contains characters that can't be verified safe"
				break
			fi
			if ! printf '%s' "$RM_W" | grep -qE "$RM_SAFE_SCRATCH|$RM_SAFE_ARTIFACT|$RM_SAFE_FIXTURE"; then
				RM_ASK_REASON="operand \"$RM_W\" is not on the known-safe path list"
				break
			fi
		done
		[ "$RM_OPERAND_COUNT" -eq 0 ] && RM_ASK_REASON="no path operand found to verify"
	fi

	if [ -z "$RM_ASK_REASON" ]; then
		jq -n --arg r "recursive delete of a known-disposable path (scratchpad/.venv/node_modules/build-artifact/tests-fixtures)" \
			'{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": $r}}'
	else
		jq -n --arg r "$RM_ASK_REASON" \
			'{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": $r}}'
	fi
	exit 0
fi

exit 0
