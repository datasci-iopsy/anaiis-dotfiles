#!/usr/bin/env bash
# tests/test-bash-guard.sh -- verify the merged PreToolUse:Bash guard keeps
# the exact block/allow semantics of the two scripts it replaced
# (block-destructive-commands.sh and prefer-jq.sh).
#
# Usage: bash tests/test-bash-guard.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_DIR/claude/hooks/bash-guard.sh"

PASS=0
FAIL=0

# run_guard <command-string>; sets RC and STDERR
run_guard() {
	local cmd="$1"
	STDERR=$(jq -n --arg c "$cmd" '{"session_id":"test","tool_input":{"command":$c}}' \
		| bash "$GUARD" 2>&1 >/dev/null)
	RC=$?
}

assert_block() {
	local name="$1" cmd="$2" needle="$3"
	run_guard "$cmd"
	if [ "$RC" -eq 2 ] && printf '%s' "$STDERR" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        exit=%s stderr=%s\n' "$name" "$RC" "$STDERR"
		FAIL=$((FAIL + 1))
	fi
}

assert_allow() {
	local name="$1" cmd="$2"
	run_guard "$cmd"
	if [ "$RC" -eq 0 ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        expected exit 0, got %s (%s)\n' "$name" "$RC" "$STDERR"
		FAIL=$((FAIL + 1))
	fi
}

echo "# 1. Destructive commands blocked"
assert_block "1.1 bq rm" "bq rm -f mydataset.mytable" "BLOCK"
assert_block "1.2 gcloud delete" "gcloud projects delete my-project" "BLOCK"
assert_block "1.3 gcloud set-iam-policy" "gcloud projects set-iam-policy p policy.json" "BLOCK"
assert_block "1.4 uv cache clean" "uv cache clean" "BLOCK"
assert_block "1.5 uv publish" "uv publish" "BLOCK"

echo "# 2. Python-for-JSON blocked"
assert_block "2.1 import json only" "python3 -c 'import json; print(json.load(open(\"f.json\")))'" "jq"

echo "# 2b. Secrets: protected paths blocked"
assert_block "2b.1 cat .env" "cat .env" "BLOCK"
assert_block "2b.2 cat nested .env.local" "cat ./app/.env.local" "BLOCK"
assert_block "2b.3 cp template onto .env" "cp .env.example .env" "BLOCK"
assert_block "2b.4 cat bashrc.local" 'cat ~/.bashrc.local' "BLOCK"
assert_block "2b.5 read ssh key" 'less ~/.ssh/id_ed25519' "BLOCK"
assert_block "2b.6 cat global secrets file" 'cat ~/.config/secrets/global.env' "BLOCK"
assert_block "2b.7 pem file" "openssl rsa -in server.pem" "BLOCK"
assert_block "2b.8 key file" "cat signing.key" "BLOCK"
assert_block "2b.9 aws credentials" 'cat ~/.aws/credentials' "BLOCK"
assert_block "2b.10 cat zshrc.local" 'cat ~/.zshrc.local' "BLOCK"
assert_block "2b.11 cat profile" 'cat ~/.profile' "BLOCK"
assert_block "2b.12 cat gcloud config" 'cat ~/.config/gcloud/application_default_credentials.json' "BLOCK"

echo "# 2c. Secrets: environment dumps blocked"
assert_block "2c.1 bare printenv" "printenv" "BLOCK"
assert_block "2c.2 piped printenv" "printenv | wc -l" "BLOCK"
assert_block "2c.3 printenv secret var" "printenv QUALTRICS_API_KEY" "BLOCK"
assert_block "2c.4 bare env" "env" "BLOCK"
assert_block "2c.5 echo secret var" 'echo $TWILIO_AUTH_TOKEN' "BLOCK"
assert_block "2c.6 printf secret var" 'printf "%s" ${CODERABBIT_API_KEY}' "BLOCK"

echo "# 3. Allowed commands pass"
assert_allow "3.1 git status" "git status"
assert_allow "3.2 bq query" "bq query --use_legacy_sql=false 'select 1'"
assert_allow "3.3 gcloud list" "gcloud projects list"
assert_allow "3.4 uv sync" "uv sync"
assert_allow "3.5 python json+pandas comma" "python3 -c 'import json, pandas; ...'"
assert_allow "3.6 python json+separate import" "python3 -c 'import json
import pandas'"
assert_allow "3.7 python no json" "python3 -c 'print(1)'"
assert_allow "3.8 empty command" ""
assert_allow "3.9 cat .env.example" "cat .env.example"
assert_allow "3.10 cat .env.template" "cat config/.env.template"
assert_allow "3.11 direnv allow" "direnv allow"
assert_allow "3.12 echo PATH" 'echo $PATH'
assert_allow "3.13 gh auth status" "gh auth status"
assert_allow "3.14 env-prefixed command" "env FOO=bar make build"

echo "# 4. Message-flag prose allowed (commit messages, PR text)"
assert_allow "4.1 commit -m single-quoted mentioning .env" "git commit -m 'docs: describe .env handling'"
assert_allow "4.2 commit -m double-quoted, no expansion" 'git commit -m "update the global.env loading docs"'
assert_allow "4.3 commit -m mentioning bashrc and ssh" 'git commit -m "deny rules now cover ~/.bashrc and ~/.ssh paths"'
assert_allow "4.4 commit -m mentioning env-dump phrase" 'git commit -m "guard blocks printenv of TOKEN vars"'
assert_allow "4.5 multiline commit message" 'git commit -m "Protect secret files

Covers .env files, secrets/ directories, and credentials stores."'
assert_allow "4.6 two -m paragraphs" 'git commit -m "subject" -m "body mentions ~/.ssh/config"'
assert_allow "4.7 --message= form" 'git commit --message="handle .env templates"'
assert_allow "4.8 git tag -m" "git tag -a v1.0 -m 'covers secrets/ dirs'"
assert_allow "4.9 gh pr title and body" 'gh pr create --title "Protect .env files" --body "Adds deny rules for .ssh and credentials paths"'
assert_allow "4.10 single quotes may contain dollar" "git commit -m 'costs \$5; also mentions .bashrc'"

echo "# 5. Message-flag bypass attempts still blocked"
assert_block "5.1 command substitution in -m" 'git commit -m "$(cat .env)"' "BLOCK"
assert_block "5.2 backtick substitution in -m" 'git commit -m "`cat .env`"' "BLOCK"
assert_block "5.3 secret var interpolated into -m" 'git commit -m "$GITHUB_TOKEN"' "BLOCK"
assert_block "5.4 quoted path outside message context" 'cat ".env"' "BLOCK"
assert_block "5.5 single-quoted path outside message context" "cat '.env'" "BLOCK"
assert_block "5.6 bash -c is not a message flag" 'bash -c "cat .env"' "BLOCK"
assert_block "5.7 clean message but second command dirty" 'git commit -m "clean message" && cat .env' "BLOCK"
assert_block "5.8 secret var in --body" 'gh pr create --body "uses $QUALTRICS_API_KEY"' "BLOCK"
assert_block "5.9 ssh dir without trailing slash" 'tar czf /tmp/x.tgz ~/.ssh' "BLOCK"
assert_allow "5.10 ssh command itself stays usable" "ssh host uptime"
assert_block "5.11 unquoted secret var in -m" 'git commit -m $OPENAI_API_KEY' "BLOCK"

echo
echo "──────────────────────────────────────────────"
echo "test-bash-guard: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
