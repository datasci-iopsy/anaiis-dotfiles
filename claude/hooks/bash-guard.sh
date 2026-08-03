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

exit 0
