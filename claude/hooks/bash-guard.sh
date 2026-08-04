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
	read -r -a RM_WORDS <<<"${CMD//$'\n'/ }"
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

	# Narrow, provably-safe carve-out: silently allow when the ENTIRE
	# command consists of nothing but mktemp-assignment statement(s)
	# followed by exactly one final recursive-rm cleanup on those exact
	# variables -- e.g. `TMP=$(mktemp -d); ...; rm -rf "$TMP"`. This does
	# NOT loosen the compound-operator ask below in general: an "allow"
	# decision covers the WHOLE submitted command, so this only fires when
	# every statement matches this exact recognized shape, leaving nothing
	# else present that could be laundered alongside the rm. A command
	# with any other statement (real work, a pipe, a second command) fails
	# to match and falls straight through to the unchanged ask logic
	# below. A later reassignment of the same variable to something other
	# than a fresh mktemp call also fails to match, since every statement
	# before the final rm must itself be a clean mktemp assignment.
	# Statements are split on ';' and real newlines only, not && / || / &
	# -- those carry conditional/background semantics this check doesn't
	# reason about, so their presence simply fails to match.
	# mktemp's own argument text (captured group 2) is a POSITIVE denylist
	# excluding every shell metacharacter capable of nested execution,
	# expansion, or redirection (backtick, $, |, &, <, >, (, ;, #, {, },
	# ~, both quote characters, backslash) -- not just the closing paren.
	# Stored in a variable, not written inline into [[ =~ ]], since this
	# file already had one instance this session where inline regex
	# escaping silently didn't behave as assumed; a variable can be
	# tested standalone. Without this exclusion, a payload hidden inside
	# mktemp's own arguments (e.g. a backtick-quoted nested command, which
	# contains no ')' character) would still match this "clean mktemp
	# assignment" shape and execute for real when the statement runs,
	# laundered through the one carve-out in this file designed
	# specifically to prevent exactly this. Caught by adversarial review
	# before this shipped; confirmed via a live PoC that a nested
	# backtick command actually ran. A second adversarial pass after the
	# fix found two low-severity, non-exploitable gaps closed by adding
	# #/{/}/~ here: a bare '#' produces a false "allow" on a command real
	# bash actually refuses to run (a mid-statement '#' with no following
	# newline comments out to true EOF, a parse-time syntax error, so
	# nothing executes -- confirmed empirically), and brace/tilde
	# expansion carry no code-execution capability here but are expansion
	# mechanisms this denylist's own stated goal should cover regardless.
	RM_MKTEMP_ASSIGN_RE='^([A-Za-z_][A-Za-z0-9_]*)=\$\([[:space:]]*mktemp([[:space:]][^)`$|&<>(;#{}~'"'"'"\\]*)?\)$'
	RM_MKTEMP_ALLOW=0
	RM_STATEMENTS_STR="${CMD//$'\n'/;}"
	IFS=';' read -r -a RM_STATEMENTS <<<"$RM_STATEMENTS_STR"
	RM_TRIMMED=()
	for RM_STMT in "${RM_STATEMENTS[@]}"; do
		RM_STMT="${RM_STMT#"${RM_STMT%%[![:space:]]*}"}"
		RM_STMT="${RM_STMT%"${RM_STMT##*[![:space:]]}"}"
		[ -n "$RM_STMT" ] && RM_TRIMMED+=("$RM_STMT")
	done
	RM_TRIMMED_COUNT=${#RM_TRIMMED[@]}
	if [ "$RM_TRIMMED_COUNT" -ge 1 ]; then
		RM_LAST_STMT="${RM_TRIMMED[$((RM_TRIMMED_COUNT - 1))]}"
		read -r -a RM_LAST_WORDS <<<"$RM_LAST_STMT"
		if [ "${#RM_LAST_WORDS[@]}" -ge 2 ]; then
			case "${RM_LAST_WORDS[0]}" in
				rm | /bin/rm | /usr/bin/rm | '\rm')
					RM_SAW_RECURSIVE_FLAG=0
					RM_ALL_VARS_OK=1
					RM_SEEN_VARNAMES=" "
					for ((RM_TI = 1; RM_TI < ${#RM_LAST_WORDS[@]}; RM_TI++)); do
						RM_TOK="${RM_LAST_WORDS[$RM_TI]}"
						case "$RM_TOK" in
							--recursive)
								RM_SAW_RECURSIVE_FLAG=1
								continue
								;;
							-[A-Za-z]*)
								[[ "$RM_TOK" =~ ^-[A-Za-z]*[rR][A-Za-z]*$ ]] && RM_SAW_RECURSIVE_FLAG=1
								continue
								;;
						esac
						# The operand must be QUOTED (starts and ends with a
						# literal '"'), not bare $VAR/${VAR}: an unquoted
						# reference is subject to the real shell's word-
						# splitting/globbing at execution time, so mktemp
						# output containing a space (e.g. --suffix=" x")
						# could silently expand into more than one operand
						# this check never independently validated.
						RM_TOK_LEN=${#RM_TOK}
						if ((RM_TOK_LEN >= 2)) && [[ "${RM_TOK:0:1}" == '"' && "${RM_TOK: -1}" == '"' ]]; then
							RM_TOK_INNER="${RM_TOK:1:RM_TOK_LEN-2}"
							if [[ "$RM_TOK_INNER" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)$ ]] || [[ "$RM_TOK_INNER" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
								RM_VARNAME="${BASH_REMATCH[1]}"
								case "$RM_SEEN_VARNAMES" in
									*" $RM_VARNAME "*) ;;
									*) RM_SEEN_VARNAMES="$RM_SEEN_VARNAMES$RM_VARNAME " ;;
								esac
							else
								RM_ALL_VARS_OK=0
								break
							fi
						else
							RM_ALL_VARS_OK=0
							break
						fi
					done
					if [ "$RM_SAW_RECURSIVE_FLAG" -eq 1 ] && [ "$RM_ALL_VARS_OK" -eq 1 ] && [ "$RM_SEEN_VARNAMES" != " " ]; then
						RM_PRECEDING_OK=1
						for ((RM_SI = 0; RM_SI < RM_TRIMMED_COUNT - 1; RM_SI++)); do
							RM_STMT="${RM_TRIMMED[$RM_SI]}"
							if [[ "$RM_STMT" =~ $RM_MKTEMP_ASSIGN_RE ]]; then
								RM_SEEN_VARNAMES="${RM_SEEN_VARNAMES/ ${BASH_REMATCH[1]} / }"
							else
								RM_PRECEDING_OK=0
								break
							fi
						done
						if [ "$RM_PRECEDING_OK" -eq 1 ] && [ "$RM_SEEN_VARNAMES" = " " ]; then
							RM_MKTEMP_ALLOW=1
						fi
					fi
					;;
			esac
		fi
	fi

	if [ "$RM_MKTEMP_ALLOW" -eq 1 ]; then
		jq -n --arg r "recursive delete of variable(s) assigned via mktemp earlier in this same command, with no other statement present to verify" \
			'{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": $r}}'
		exit 0
	fi

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
