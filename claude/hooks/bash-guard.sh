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

# Scans below feed strings to grep/sed via here-strings rather than
# `printf | ...` pipelines: the pipeline forks a subshell for the builtin
# printf on top of the exec, and this hook runs on every Bash call, so one
# fork per scan is the dominant cost. Semantics are unchanged for grep -q
# (per-line matching, same anchors); the here-string's trailing newline is
# stripped by $(...) where output is captured.
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
SESSION_ID=$(jq -r '.session_id // empty' <<<"$INPUT")

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
if grep -qE '^bq\s+rm\b' <<<"$CMD"; then
	printf 'BLOCK: bq rm is destructive. Run this manually in terminal.\n' >&2
	exit 2
fi

if grep -qE '^gcloud\s.*(delete|destroy|remove-iam-policy|set-iam-policy|disable|reset-windows-password)' <<<"$CMD"; then
	printf 'BLOCK: Destructive gcloud command detected. Run this manually in terminal.\n' >&2
	exit 2
fi

if grep -qE '^uv\s+(cache\s+(clean|prune)|publish|tool\s+uninstall|pip\s+uninstall)' <<<"$CMD"; then
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
if grep -qE '(^|[;&|]\s*)git\s+push\b' <<<"$CMD" \
	&& grep -qE '(^|[[:space:]])(-f|--force)([[:space:]=]|$)' <<<"$CMD"; then
	printf 'BLOCK: bare --force/-f push is unsafe (no remote-side check). Use --force-with-lease instead.\n' >&2
	exit 2
fi

# ── Secrets: token-minting commands ─────────────────────────────────────────
# These commands take no file path (so the protected-path check below never
# sees them) but their sole output is a live, usable credential.
if grep -qE '(^|[;&|]\s*)gcloud\s+auth\s+print-(access|identity)-token\b|(^|[;&|]\s*)aws\s+sts\s+get-(session|federation)-token\b|(^|[;&|]\s*)heroku\s+auth:token\b|(^|[;&|]\s*)doctl\s+auth\s+token\b' <<<"$CMD"; then
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
if grep -qE '(^|[[:space:]])(-m|--message|--title|--body|--notes|--description)(=|[[:space:]]+)("[^"]*\$\{?[A-Za-z0-9_]*(TOKEN|SECRET|API_?KEY|PASSWORD)|\$\{?[A-Za-z_][A-Za-z0-9_]*(TOKEN|SECRET|API_?KEY|PASSWORD))' <<<"$CMD"; then
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
		# grep/egrep/rg search PATTERN is regex text, not a file path -- a
		# protected token quoted as the pattern is not a real read. Only the
		# quoted token immediately after the command name and its flags is
		# stripped, never a later argument, so a real FILE operand is
		# untouched and still scanned below.
		# A pattern-file flag (-f/--file/--from-file) ends the flag run: its
		# operand is a file and the positional after it is the input file, so
		# neither is scrubbed. A path-selecting flag (--include/--exclude/
		# --glob/--iglob and rg\x27s short -g) has its own operand consumed and
		# preserved; the next quoted token afterward is still scrubbed as the pattern.
		my $pfstop = qr/(?:file|from-file|rawfile|slurpfile|argfile)/;
		my $pfskip = qr/(?:include|exclude|exclude-dir|include-dir|glob|iglob|ignore-file|exclude-from|pre)/;
		my $gtok = qr/(?:\x27[^\x27]*\x27|"[^"`\$]*"|\S+)/;
		my $gelem1 = qr/-(?![A-Za-z]*[fg]\b)[A-Za-z]+|--(?!(?:$pfstop|$pfskip)\b)[A-Za-z][A-Za-z-]*(?:=\S*|\s+(?![\x27"])\S+)?/;
		my $gelem2 = qr/(?:-[A-Za-z]*g\b|--$pfskip\b)(?:=$gtok|\s+$gtok)/;
		my $g = qr/(?:grep|egrep|rg)/;
		s/((?:^|[;&|]\s*)$g\b(?:\s+(?:$gelem2|$gelem1))*\s+)\x27[^\x27]*\x27/${1}\x27\x27/gs;
		s/((?:^|[;&|]\s*)$g\b(?:\s+(?:$gelem2|$gelem1))*\s+)"[^"`\$]*"/${1}""/gs;
		# The jq program is a filter expression, not a file path, and commonly
		# appears after a shell keyword (a for-loop body\x27s "do") that the
		# grep/rg separator anchor above would miss, so this one anchors on
		# the bare word instead. Still strictly local: only the quoted token
		# right after jq (and its flags) is blanked, never anything before or
		# after, so a real path elsewhere in the same command is untouched.
		s/(\bjq\b(?:\s+-(?!-?(?:f\b|[A-Za-z]*f\b|-file\b|-from-file\b|-rawfile\b|-slurpfile\b|-argfile\b))-?[A-Za-z][A-Za-z-]*)*\s+)\x27[^\x27]*\x27/${1}\x27\x27/gs;
		s/(\bjq\b(?:\s+-(?!-?(?:f\b|[A-Za-z]*f\b|-file\b|-from-file\b|-rawfile\b|-slurpfile\b|-argfile\b))-?[A-Za-z][A-Za-z-]*)*\s+)"[^"`\$]*"/${1}""/gs;
		# echo/printf\x27s quoted arguments are text being printed (to stdout, a
		# log line, a ledger file), not a file path read. Every static quoted
		# token right after echo/printf (and its flags) is blanked in turn; a
		# redirect target after it (echo "..." > .env) is never touched and
		# still scanned below.
		my $e = qr/(?:echo|printf)/;
		my $eflag = qr/-{1,2}[A-Za-z][A-Za-z-]*/;
		my $eblank = qr/(?:\x27\x27|"")/;
		my $ebare = qr/[^\s\x27"<>|;&()`\$]+/;
		1 while s/(\b$e\b(?:\s+(?:$eflag|$eblank|$ebare))*\s+)\x27[^\x27]+\x27/${1}\x27\x27/s;
		1 while s/(\b$e\b(?:\s+(?:$eflag|$eblank|$ebare))*\s+)"[^"`\$]+"/${1}""/s;
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
# Finally, strip a .env path under tests/fixtures/ -- that's test scaffolding,
# not a real secret. The repeated directory-segment group explicitly excludes
# segments starting with "." (rules out ".." specifically), so a traversal
# escaping the fixtures dir (tests/fixtures/../../.env) never matches and
# still gets caught below.
# A jq file-valued flag (-f/--file/--from-file and combined forms like -nf)
# makes the quoted token a real path, not a filter key, so this fallback
# .env-key stripper must not fire when one is present.
JQ_DOTENV_SED="s/(jq([[:space:]]+--?[A-Za-z][A-Za-z-]*)*[[:space:]]+)(['\"])\.env([^A-Za-z0-9_]|\$)/\1\3\4/g"
if grep -qE '\bjq\b[^|;&]*[[:space:]]-(-?f\b|[A-Za-z]*f\b|-file\b|-from-file\b|-rawfile\b|-slurpfile\b|-argfile\b)' <<<"$GUARD_STR"; then
	JQ_DOTENV_SED='s/&/&/'
fi
# Code idioms that read the process environment are not file paths. Each form needs a non-name
# character before it (a file named myprocess.env still matches below) and, for process.env, an
# upper-case variable name or "[" after it (a file named process.env.local still matches below).
CODE_ENV_SED='s/(^|[^A-Za-z0-9_.-])(process\.env\.[A-Z_][A-Z0-9_]*|process\.env\[|import\.meta\.env|Deno\.env\.(get|set|has|delete|toObject))/\1/g'
SCRUBBED=$(sed -E -e 's/\.env\.(example|template)//g' \
	-e "$JQ_DOTENV_SED" \
	-e "$CODE_ENV_SED" \
	-e 's#tests/fixtures/([^./[:space:]][^/[:space:]]*/)*\.env(\.[A-Za-z0-9_]+)*#tests/fixtures/FIXTURE#g' <<<"$GUARD_STR")
# "credentials" matches only as a file name (credentials.json) or a path component (/credentials),
# not as a word in prose, a grep pattern, or SQL text.
# shortcut: `.key` also matches attribute access such as a.key, because text cannot tell it from
# server.key; the guard fails closed. Upgrade when the guard parses shell instead of matching text.
SECRET_RE='(\.env\b|\.ssh\b|\.bashrc(\.local)?|\.bash_profile|\.zshrc(\.local)?|\.profile\b|secrets/|\.pem\b|(^|[/[:space:]])\.?\w*\.key\b|[A-Za-z0-9_.-]*credentials[A-Za-z0-9_-]*\.(json|db|ya?ml|ini|toml|txt|csv|conf|cfg)\b|/credentials([^A-Za-z0-9_.-]|$)|\.aws\b|\.config/(gcloud|secrets|gh)\b|\.netrc\b|\.gnupg\b|\.docker/config|\.kube/config|\.npmrc\b|\.pypirc\b)'
if grep -qE "$SECRET_RE" <<<"$SCRUBBED"; then
	# Name only the matched token, never the rest of the command, so the message cannot leak a value.
	MATCHED=$(grep -oE "$SECRET_RE" <<<"$SCRUBBED" | head -n 1 | sed -E 's#^[[:space:]/]+##; s#[[:space:]]+$##')
	log_secret_block "bash-guard:protected-path" "$CMD"
	printf 'BLOCK: command references a protected secrets path (matched: %s). If a value is needed, ask the user to provide or load it.\n' "$MATCHED" >&2
	exit 2
fi

# ── Secrets: environment dumps ──────────────────────────────────────────────
# Bare env/printenv (no pipe) is always a full dump, blocked outright. Piped
# forms are more nuanced: a genuinely targeted lookup (env | grep <var>, or a
# bare count via wc) reveals nothing when the search term/output isn't itself
# secret-shaped, so those stay allowed. A targeted lookup requires a single
# positive, anchored variable-name selector as the whole pattern (the complete
# variable name followed by "=", optionally "^"-anchored; no -v/
# --invert-match, no regex metacharacters, nothing piped or appended after
# it); anything looser (a viewer like cat/less/head/tail/sort/tee, an extra
# stage after the pattern, or a grep/egrep/rg whose selector is secret-shaped
# or not a complete variable name followed by "=") is still effectively a
# dump and stays blocked. Only a fixed whitelist of grep short options that
# cannot select, invert, or emit more than the matched line is accepted.
# Calibrated against real usage, see tests/fixtures/env-dump/usage-evidence.md.
ENV_DUMP=false
if grep -qE '^[[:space:]]*(printenv|env)[[:space:]]*$' <<<"$CMD"; then
	ENV_DUMP=true
elif grep -qE '^[[:space:]]*(printenv|env)[[:space:]]*\|' <<<"$CMD"; then
	if grep -qE '^[[:space:]]*(printenv|env)[[:space:]]*\|[[:space:]]*(grep|egrep|rg)\b' <<<"$CMD"; then
		if grep -qE '^[[:space:]]*(printenv|env)[[:space:]]*\|[[:space:]]*(grep|egrep|rg)([[:space:]]+-[inwxFEGPsaHhbco]+)*[[:space:]]+('"'"'\^?[A-Za-z_][A-Za-z0-9_]*='"'"'|"\^?[A-Za-z_][A-Za-z0-9_]*="|\^?[A-Za-z_][A-Za-z0-9_]*=)[[:space:]]*$' <<<"$CMD" \
			&& ! grep -qiE '(^|[[:space:]])(-[A-Za-z]*v[A-Za-z]*|--invert-match)([[:space:]]|$)' <<<"$CMD" \
			&& ! grep -qiE '(TOKEN|SECRET|API_?KEY|PASSWORD)' <<<"$CMD"; then
			ENV_DUMP=false
		else
			ENV_DUMP=true
		fi
	elif grep -qE '^[[:space:]]*(printenv|env)[[:space:]]*\|[[:space:]]*wc\b' <<<"$CMD"; then
		ENV_DUMP=false
	else
		ENV_DUMP=true
	fi
fi

if $ENV_DUMP \
	|| grep -qE 'printenv[[:space:]]+.*(TOKEN|SECRET|API_?KEY|PASSWORD)' <<<"$GUARD_STR" \
	|| grep -qE '\b(echo|printf)\b[^|;&]*\$\{?[A-Za-z0-9_]*(TOKEN|SECRET|API_?KEY|PASSWORD)' <<<"$GUARD_STR"; then
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
if grep -qE '(os\.environ|process\.env)\)|os\.environ\.(items|keys|values)\(\)|\bENV\.(to_h|inspect)\b' <<<"$CMD" \
	|| { grep -qE '(os\.getenv|os\.environ\[|process\.env\.|ENV\[)' <<<"$CMD" \
		&& grep -qiE '(TOKEN|SECRET|API_?KEY|PASSWORD)' <<<"$CMD"; }; then
	log_secret_block "bash-guard:env-dump-lang" "$CMD"
	printf 'BLOCK: command would print language-level environment secrets (python/node/ruby). If a value is needed, ask the user to provide it.\n' >&2
	exit 2
fi

# ── Prefer jq over Python for pure JSON parsing ─────────────────────────────
# Only python/python3 commands whose sole import is json are blocked. A comma
# after json (import json, pandas) or any other import statement means the
# script does more than parsing; allow it.
if grep -qE '\b(python|python3)\b' <<<"$GUARD_STR" \
	&& grep -qE '\bimport\s+json\b' <<<"$GUARD_STR" \
	&& ! grep -qE '\bimport\s+json\s*,' <<<"$GUARD_STR" \
	&& ! sed 's/import[[:space:]]*json//g' <<<"$GUARD_STR" | grep -qE '\bimport\s+\w'; then
	echo "Prefer jq over Python for JSON parsing -- import json is the only import, this is a pure parsing task. jq is pre-approved, streaming, and faster." >&2
	exit 2
fi

# ── uv add/pip install: transparency notice ─────────────────────────────────
# uv is the sole sanctioned Python dependency tool (rules/python.md); these two
# subcommands are allowed, never blocked. This notice makes a dependency
# change visible in the transcript instead of silent, it never gates anything.
if grep -qE '\buv\s+add\b' <<<"$CMD"; then
	echo "[deps] $CMD -- modifies pyproject.toml/uv.lock" >&2
elif grep -qE '\buv\s+pip\s+install\b' <<<"$CMD"; then
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
# (unlike settings.json rule matching), so a static check alone must never
# emit "allow" for a compound command: rm -rf .venv && rm -rf /etc must not
# get laundered through an allow keyed off the first-looking operand.
#
# One carve-out exists (rm_wrap_eligible, below; stream e-bash-guard-rm).
# If every statement of the command is on a short vetted list, the hook
# returns an updatedInput command that first sources safe-rm.sh. That file
# replaces rm with a function that checks each expanded operand against the
# deletion roots. The shell, not this parser, then verifies each path. The
# decision is "allow" only after a first-use canary proved that the harness
# applies updatedInput (see the canary paragraph below); before that it is
# "ask". If any statement is not vetted, the hook emits "ask" as before.
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
# syscalls) this file doesn't otherwise use. The run-time guard in
# safe-rm.sh does resolve symlinks in the parent path, so a compound command
# that gets the rewrite does not have this gap. A standalone command that
# matches the static safe-list still has it.
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
if grep -qE "$RM_GATE_RE" <<<"$RM_GATE_SCAN_STR"; then
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

	# ── Cache-rm-then-runner carve-out (issue #15) ────────────────────────
	# The operator check below asks for every compound command, and the one
	# shape observed to trip it (13 of 13 prompts in the 2026-08 transcript
	# audit) is a cache-directory rm chained onto the command that needs the
	# cache gone: `rm -rf .ruff_cache && uv run ruff check x.py`. Allow that
	# shape and only that shape. A PreToolUse allow covers the whole command
	# string and bypasses the permission system for every statement in it, so
	# each condition is load-bearing, not cosmetic:
	#   1. Statement separators are limited to &&, ;, and newline. Any |, ||,
	#      lone &, $, backtick, parenthesis, <, or > anywhere in the raw
	#      command (quotes included) disqualifies: pipes, substitutions, and
	#      redirections can carry anything.
	#   2. Exactly one word in the whole command is an rm invocation, and no
	#      word is another deletion-capable command (rmdir, unlink, shred,
	#      find, xargs, or git clean).
	#   3. The rm statement starts with rm, carries a recursive flag, has at
	#      least one operand, and every operand is a literal path on the cache
	#      list: .ruff_cache,
	#      .pytest_cache, .mypy_cache, .tox, __pycache__, .venv, node_modules,
	#      optionally under a relative directory prefix whose segments do not
	#      start with a dot (so never ..). dist, build, .next, and coverage
	#      stay off this list: they can hold real output, and remain allowed
	#      only in the standalone form via RM_ARTIFACTS below.
	#   4. Every other statement's first word is a known runner: uv, ruff,
	#      pytest, python, python3, npm, npx, pnpm, yarn, make, Rscript,
	#      quarto, dbt, sqlfmt, shfmt, shellcheck, echo, cd, ls.
	# Anything else falls through to the operator check unchanged. Checks use
	# bash pattern matching on the raw CMD (not GUARD_STR, whose quoted spans
	# are blanked) so nothing inside quotes can hide a second statement.
	RM_CACHE_ALLOW=0
	RM_CACHE_FORBID='[|`$()<>]'
	if ! [[ "$CMD" =~ $RM_CACHE_FORBID ]]; then
		RM_CACHE_NORM="${CMD//$'\n'/;}"
		RM_CACHE_NORM="${RM_CACHE_NORM//&&/;}"
		if [[ "$RM_CACHE_NORM" != *'&'* ]]; then
			RM_CACHE_RM_COUNT=0
			RM_CACHE_OTHER_DELETE=0
			RM_CACHE_PREV=""
			for RM_CW in "${RM_WORDS[@]}"; do
				case "$RM_CW" in
					rm | */rm | '\rm') RM_CACHE_RM_COUNT=$((RM_CACHE_RM_COUNT + 1)) ;;
					rmdir | unlink | shred | find | xargs) RM_CACHE_OTHER_DELETE=1 ;;
					clean) [ "$RM_CACHE_PREV" = "git" ] && RM_CACHE_OTHER_DELETE=1 ;;
				esac
				RM_CACHE_PREV="$RM_CW"
			done
			if [ "$RM_CACHE_RM_COUNT" -eq 1 ] && [ "$RM_CACHE_OTHER_DELETE" -eq 0 ]; then
				IFS=';' read -r -a RM_CACHE_STMTS <<<"$RM_CACHE_NORM"
				RM_CACHE_OK=1
				RM_CACHE_RM_STMTS=0
				RM_CACHE_RUNNER_STMTS=0
				RM_CACHE_LITERAL_RE='^[A-Za-z0-9._/-]+$'
				RM_CACHE_PATH_RE='^(\./)?([^./][^/]*/)*(\.ruff_cache|\.pytest_cache|\.mypy_cache|\.tox|__pycache__|\.venv|node_modules)/?$'
				for RM_CS in "${RM_CACHE_STMTS[@]}"; do
					read -r -a RM_CSW <<<"$RM_CS"
					[ "${#RM_CSW[@]}" -eq 0 ] && continue
					case "${RM_CSW[0]}" in
						rm | */rm | '\rm')
							RM_CACHE_RM_STMTS=$((RM_CACHE_RM_STMTS + 1))
							RM_CACHE_OPERANDS=0
							RM_CACHE_DD=0
							RM_CACHE_RECURSIVE=0
							for ((RM_CI = 1; RM_CI < ${#RM_CSW[@]}; RM_CI++)); do
								RM_CO="${RM_CSW[$RM_CI]}"
								if [ "$RM_CACHE_DD" -eq 0 ]; then
									if [ "$RM_CO" = "--" ]; then
										RM_CACHE_DD=1
										continue
									fi
									case "$RM_CO" in
										--recursive)
											RM_CACHE_RECURSIVE=1
											continue
											;;
										-*)
											[[ "$RM_CO" =~ ^-[A-Za-z]*[rR][A-Za-z]*$ ]] && RM_CACHE_RECURSIVE=1
											continue
											;;
									esac
								fi
								RM_CACHE_OPERANDS=$((RM_CACHE_OPERANDS + 1))
								if ! [[ "$RM_CO" =~ $RM_CACHE_LITERAL_RE ]] || ! [[ "$RM_CO" =~ $RM_CACHE_PATH_RE ]]; then
									RM_CACHE_OK=0
								fi
							done
							[ "$RM_CACHE_OPERANDS" -eq 0 ] && RM_CACHE_OK=0
							[ "$RM_CACHE_RECURSIVE" -eq 1 ] || RM_CACHE_OK=0
							;;
						uv | ruff | pytest | python | python3 | npm | npx | pnpm | yarn | make | Rscript | quarto | dbt | sqlfmt | shfmt | shellcheck | echo | cd | ls)
							RM_CACHE_RUNNER_STMTS=$((RM_CACHE_RUNNER_STMTS + 1))
							;;
						*) RM_CACHE_OK=0 ;;
					esac
				done
				# Compound commands only: a standalone rm keeps taking the
				# safe-list path below, so its decision and reason are unchanged.
				[ "$RM_CACHE_RM_STMTS" -eq 1 ] && [ "$RM_CACHE_RUNNER_STMTS" -ge 1 ] || RM_CACHE_OK=0
				RM_CACHE_ALLOW=$RM_CACHE_OK
			fi
		fi
	fi
	if [ "$RM_CACHE_ALLOW" -eq 1 ]; then
		jq -n --arg r "single recursive rm of a known cache directory, chained only to known runner commands (issue #15 carve-out)" \
			'{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": $r}}'
		exit 0
	fi

	# ── Run-time-verified rm (stream e-bash-guard-rm, D-026 to D-029) ──────
	# The catch-all ask below exists because a static parser cannot check each
	# path of a compound command. The shell can, after it expands variables and
	# globs. So for a command whose EVERY statement is on a short vetted list,
	# this section returns allow and rewrites the command (updatedInput) so
	# that it first sources claude/hooks/safe-rm.sh. That file defines an rm
	# function that checks each expanded operand against explicit deletion
	# roots and deletes nothing unless all pass. A refusal at run time stops
	# the WHOLE command (the function exits the shell); the user can then run
	# the delete as its own call with a literal path, which still asks.
	#
	# An allow covers the whole command and skips every prompt in it, so the
	# vetting is deliberately small and strict (the same invariant as the cache
	# carve-out above): one statement that is not on the list means ask.
	# Vetted statements, and only these:
	#   - rm as the plain head word, with at least one operand. A single-quoted
	#     operand, a glob operand, an operand that starts with ~, and an operand
	#     that holds $HOME make the command ask. A fully literal operand must pass
	#     the safe-list. An operand with a variable inside double quotes ("$S/x")
	#     is checked at run time only, by the rm function.
	#   - these heads: cd ls echo printf pwd true false test [ basename dirname.
	#     mkdir is vetted too, but only for plain literal operands that pass the
	#     safe-list. Runners (uv, make, python, and so on), cat, touch, and the
	#     filter words are not statement heads: a child program runs the real rm,
	#     outside the function.
	#   - after a pipe, only grep head tail wc cut tr basename dirname. The left
	#     side of a pipe must not be an rm statement or a loop.
	#   - a literal assignment of one word, never to a name on the deny list
	#     (PATH, IFS, HOME, __SAFE_RM_*, and others). The value holds no $.
	#   - for NAME in <literal words>, with the same name deny list for NAME, and
	#     the keywords do done if then else fi.
	#   - the redirections >/dev/null, 2>/dev/null, 2>&1, >&2, each followed by a
	#     blank or the end of the command.
	# Every word of every statement, quotes removed, is also checked against a deny
	# set (rm outside head position, rmdir, find, xargs, sudo, eval, bash, git, mv,
	# and others), and a printf statement with a -v word asks. Forbidden anywhere:
	# a backtick, a backslash, < > ( ) { } ! a lone &, and a $ that does not start
	# a plain $NAME.
	# First-use canary (D-E-15). The decision depends on a sentinel file,
	# $HOME/.claude/state/safe-rm-canary-<crc>-<size>, where crc and size come
	# from cksum of $HOME/.claude/hooks/safe-rm.sh. With the sentinel, the hook
	# returns allow plus updatedInput. Without it, the hook returns ask plus the
	# same updatedInput, and the prefix writes the sentinel after safe-rm.sh
	# loaded and rm is a function. If the harness ignores updatedInput, nothing
	# writes the sentinel and every later run asks. A change to safe-rm.sh
	# changes the key and asks once more. If safe-rm.sh is unreadable, the hook
	# asks with no rewrite. The prefix also exits 97 when the file loads but
	# defines no rm function (an empty or foreign file).
	# Accepted risk (D-E-16): an agent that writes the sentinel by hand or edits
	# claude/hooks/ is out of scope. The guard stops accidents, not an adversary.
	RM_SEG='([^./][^/]*/)*[^./][^/]*'
	RM_ARTIFACTS='\.venv|node_modules|dist|build|\.next|coverage|__pycache__'
	RM_SAFE_SCRATCH="^(/private)?/tmp/claude-[0-9]+/${RM_SEG}/scratchpad(/${RM_SEG})?/?\$"
	RM_SAFE_ARTIFACT="^(\\./)?(${RM_SEG}/)?(${RM_ARTIFACTS})(/${RM_SEG})?/?\$"
	RM_SAFE_FIXTURE="^(\\./)?tests/fixtures/${RM_SEG}/?\$"
	RM_SAFE_ANY="$RM_SAFE_SCRATCH|$RM_SAFE_ARTIFACT|$RM_SAFE_FIXTURE"

	# rm_name_denied <name>: return 0 for a variable name that a vetted statement must not assign.
	# One list serves NAME=value and the for loop variable. __SAFE_RM_* are the guard's own variables.
	rm_name_denied() {
		case "$1" in
			PATH | IFS | HOME | TMPDIR | ENV | SHELLOPTS | PS[0-9] | PROMPT_COMMAND | CDPATH | GLOBIGNORE | SHELL | USER | LOGNAME | PWD | OLDPWD | TERM | LD_* | DYLD_* | BASH* | __SAFE_RM_*) return 0 ;;
		esac
		return 1
	}

	# rm_word_denied <word>: return 0 for a word that deletes, runs another program, or changes the
	# shell. The scan checks every word of every statement, so a runner cannot carry one as an argument.
	rm_word_denied() {
		case "$1" in
			rm | rmdir | unlink | shred | find | xargs | sudo | eval | exec | source | . | env | nohup | command | builtin | alias | unalias | unset | trap | bash | sh | zsh | dash | git | docker | mv | dd | truncate | rsync) return 0 ;;
		esac
		return 1
	}

	# rm_wrap_eligible <raw-command>: return 0 when every statement is vetted.
	# What the hook checks: the statement head, every word against the deny set, the names that a
	# statement assigns, the words of a for list, and the literal operands of rm. What it leaves to
	# the run-time guard: an operand with a variable inside double quotes (for example "$S/x"). The
	# run-time guard checks that path after the shell expands it.
	rm_wrap_eligible() {
		local v="$1" stmt first var value tok tok_s w ws i dd operands rm_seen=0 pipe_next=0 prev="" stripped
		local in_d='2>/dev/null ' in_a='>/dev/null ' in_b='2>&1 ' in_c='>&2 ' amp2='&&' bar2='||' nl=$'\n' tab=$'\t' dq='"' sq="'"
		local sep=' ; ' pipemark=' ;|; '
		# shellcheck disable=SC2016
		local dollar_re='\$([^A-Za-z_]|$)' name_re='^[A-Za-z_][A-Za-z0-9_]*$'
		local value_re='^["]?[A-Za-z0-9._/:@%+,=-]*["]?$' literal_re='^[A-Za-z0-9._/-]+$'
		local -a stmts words
		# Every separator becomes a lone ; so the redirect strip below sees a blank after each redirect.
		# A pipe stays visible as its own statement (a lone |), so a pipe target can be checked.
		v="${v//$tab/ }"
		v="${v//$nl/$sep}"
		v="${v//$amp2/$sep}"
		v="${v//$bar2/$sep}"
		v="${v//;/$sep}"
		v="${v//|/$pipemark}"
		# A redirect is stripped only when a blank or the end of the string follows it (F11a).
		v="$v "
		v="${v//$in_d/  }"
		v="${v//$in_a/  }"
		v="${v//$in_b/  }"
		v="${v//$in_c/  }"
		# shellcheck disable=SC1003
		case "$v" in
			*'`'* | *'\'* | *'<'* | *'>'* | *'('* | *')'* | *'{'* | *'}'* | *'!'* | *'&'*) return 1 ;;
		esac
		[[ "$v" =~ $dollar_re ]] && return 1
		IFS=';' read -r -a stmts <<<"$v"
		[ "${#stmts[@]}" -gt 0 ] || return 1
		for stmt in "${stmts[@]}"; do
			read -r stmt <<<"$stmt"
			if [ "$stmt" = "|" ]; then
				# The left side of a pipe runs in a subshell, where a refusal would not stop the command.
				case "$prev" in
					rm | close) return 1 ;;
				esac
				pipe_next=1
				continue
			fi
			stripped=0
			while :; do
				case "$stmt" in
					"do "* | "then "* | "else "* | "if "*)
						stmt="${stmt#* }"
						read -r stmt <<<"$stmt"
						stripped=1
						;;
					do | then | else)
						stmt=""
						stripped=1
						break
						;;
					fi | done)
						stmt=""
						stripped=1
						prev=close
						break
						;;
					*) break ;;
				esac
			done
			# A keyword on the right side of a pipe would run its body in a subshell.
			[ "$stripped" -eq 0 ] || [ "$pipe_next" -eq 0 ] || return 1
			[ -n "$stmt" ] || continue
			read -r -a words <<<"$stmt"
			first="${words[0]}"
			for ((i = 0; i < ${#words[@]}; i++)); do
				w="${words[$i]}"
				# $dq and $sq stay unquoted inside ${}: each is one quote character with no glob meaning,
				# and a quoted form inside double quotes breaks on bash 3.2.
				# shellcheck disable=SC2295
				ws="${w//$dq/}"
				# shellcheck disable=SC2295
				ws="${ws//$sq/}"
				# printf -v writes a variable by name, so the guard's own variables are reachable.
				[ "$first" = printf ] && [ "$ws" = "-v" ] && return 1
				if rm_word_denied "$ws"; then
					[ "$i" -eq 0 ] && [ "$w" = rm ] || return 1
				fi
			done
			if [ "$pipe_next" -eq 1 ]; then
				case "$first" in
					grep | head | tail | wc | cut | tr | basename | dirname) ;;
					*) return 1 ;;
				esac
				pipe_next=0
				prev=""
				continue
			fi
			if [ "$first" = for ]; then
				[ "${#words[@]}" -ge 3 ] || return 1
				[[ "${words[1]}" =~ $name_re ]] || return 1
				[ "${words[2]}" = in ] || return 1
				rm_name_denied "${words[1]}" && return 1
				for ((i = 3; i < ${#words[@]}; i++)); do
					[[ "${words[$i]}" =~ $literal_re ]] || return 1
				done
				prev=""
				continue
			fi
			if [[ "$first" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
				var="${BASH_REMATCH[1]}"
				[ "${#words[@]}" -eq 1 ] || return 1
				rm_name_denied "$var" && return 1
				value="${first#*=}"
				[[ "$value" =~ $value_re ]] || return 1
				prev=""
				continue
			fi
			prev=""
			case "$first" in
				rm)
					prev="rm"
					rm_seen=$((rm_seen + 1))
					operands=0
					dd=0
					for ((i = 1; i < ${#words[@]}; i++)); do
						tok="${words[$i]}"
						if [ "$dd" -eq 0 ]; then
							case "$tok" in
								--)
									dd=1
									continue
									;;
								-*) continue ;;
							esac
						fi
						operands=$((operands + 1))
						# A single-quoted or glob operand is never vetted here (F5).
						# shellcheck disable=SC2295
						case "$tok" in
							*$sq* | *'*'* | *'?'* | *'['*) return 1 ;;
						esac
						# shellcheck disable=SC2295
						tok_s="${tok#$dq}"
						# shellcheck disable=SC2295
						tok_s="${tok_s%$dq}"
						# shellcheck disable=SC2016
						case "$tok_s" in
							'~'* | *'$HOME'*) return 1 ;;
						esac
						if [[ "$tok_s" =~ $literal_re ]]; then
							grep -qE "$RM_SAFE_ANY" <<<"$tok_s" || return 1
						fi
					done
					[ "$operands" -ge 1 ] || return 1
					;;
				mkdir)
					# mkdir stays only for plain literal operands on the static safe-list (no $, no glob).
					# A runner or another program could create a path outside every root, so no operand
					# is left to the run-time guard here.
					dd=0
					for ((i = 1; i < ${#words[@]}; i++)); do
						tok="${words[$i]}"
						if [ "$dd" -eq 0 ]; then
							case "$tok" in
								--)
									dd=1
									continue
									;;
								-*) continue ;;
							esac
						fi
						# shellcheck disable=SC2295
						tok_s="${tok#$dq}"
						# shellcheck disable=SC2295
						tok_s="${tok_s%$dq}"
						[[ "$tok_s" =~ $literal_re ]] || return 1
						grep -qE "$RM_SAFE_ANY" <<<"$tok_s" || return 1
					done
					;;
				cd | ls | echo | printf | pwd | true | false | test | '[' | basename | dirname) ;;
				*) return 1 ;;
			esac
		done
		[ "$rm_seen" -ge 1 ]
	}

	if grep -qE '[;&|`$()<>]' <<<"$GUARD_STR" || [[ "$GUARD_STR" == *$'\n'* ]]; then
		if rm_wrap_eligible "$CMD"; then
			RM_WRAP_CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
			RM_WRAP_SCRATCH=$(jq -r '.scratchpad_dir // empty' <<<"$INPUT")
			# First-use canary (D-E-15). The key is the cksum of safe-rm.sh as this process sees it:
			# <crc>-<size>. If the file is unreadable, there is no key and the command asks, with no rewrite.
			RM_WRAP_KEY=""
			if [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/hooks/safe-rm.sh" ]; then
				read -r RM_CK_CRC RM_CK_SIZE _ <<<"$(cksum <"$HOME/.claude/hooks/safe-rm.sh" 2>/dev/null)"
				[ -n "$RM_CK_CRC" ] && [ -n "$RM_CK_SIZE" ] && RM_WRAP_KEY="$RM_CK_CRC-$RM_CK_SIZE"
			fi
			if [ -n "$RM_WRAP_CWD" ] && [ -n "$RM_WRAP_KEY" ]; then
				# $HOME stays literal here on purpose: the shell that runs the command expands it. The prefix
				# loads safe-rm.sh and exits 97 unless rm is then a function (an empty or foreign file loads
				# with status 0 and defines nothing).
				# shellcheck disable=SC2016
				RM_WRAP_PREFIX=$(printf '__SAFE_RM_CWD=%q; __SAFE_RM_SCRATCH=%q; . "$HOME/.claude/hooks/safe-rm.sh" && [ "$(type -t rm)" = function ] || exit 97' "$RM_WRAP_CWD" "$RM_WRAP_SCRATCH")
				if [ -f "$HOME/.claude/state/safe-rm-canary-$RM_WRAP_KEY" ]; then
					RM_WRAP_DECISION="allow"
					RM_WRAP_WHY="every statement is vetted; rm is replaced by a run-time guard that checks each expanded path (stream e-bash-guard-rm)"
				else
					# No sentinel: ask, and let the prefix write the sentinel after the guard loaded. If the harness
					# does not apply updatedInput, nothing writes it and every later run asks again.
					RM_WRAP_DECISION="ask"
					RM_WRAP_WHY="first use of this guard version: every statement is vetted and rm is replaced by a run-time guard. Confirm once. This run writes a marker after the guard loads, and later runs of this version do not prompt (stream e-bash-guard-rm)"
					# shellcheck disable=SC2016
					RM_WRAP_PREFIX="$RM_WRAP_PREFIX; "'mkdir -p "$HOME/.claude/state" && : >"$HOME/.claude/state/safe-rm-canary-'"$RM_WRAP_KEY"'"'
				fi
				jq -n --argjson ti "$(jq -c '.tool_input' <<<"$INPUT")" \
					--arg c "${RM_WRAP_PREFIX}"$'\n'"${CMD}" \
					--arg d "$RM_WRAP_DECISION" \
					--arg r "$RM_WRAP_WHY" \
					'{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": $d, "permissionDecisionReason": $r, "updatedInput": ($ti + {"command": $c})}}'
				exit 0
			fi
		fi
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
		# RM_SEG, RM_ARTIFACTS, and the RM_SAFE_* patterns are defined once,
		# above the run-time-verified rm section, and shared by both paths.
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
			if ! grep -qE '^[A-Za-z0-9._/-]+$' <<<"$RM_W"; then
				RM_ASK_REASON="operand \"$RM_W\" contains characters that can't be verified safe"
				break
			fi
			if ! grep -qE "$RM_SAFE_SCRATCH|$RM_SAFE_ARTIFACT|$RM_SAFE_FIXTURE" <<<"$RM_W"; then
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
