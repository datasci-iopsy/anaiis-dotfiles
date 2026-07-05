#!/usr/bin/env bash
# tests/test-bash-guard.sh -- verify the merged PreToolUse:Bash guard keeps
# the exact block/allow semantics of the two scripts it replaced
# (block-destructive-commands.sh and prefer-jq.sh).
#
# Usage: bash tests/test-bash-guard.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_DIR/claude/hooks/bash-guard.sh"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

PASS=0
FAIL=0

# run_guard <command-string>; sets RC and STDERR
run_guard() {
	local cmd="$1"
	STDERR=$(jq -n --arg c "$cmd" '{"session_id":"test","tool_input":{"command":$c}}' \
		| HOME="$TEST_HOME" bash "$GUARD" 2>&1 >/dev/null)
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

LOG_FILE="$TEST_HOME/.claude/logs/secret-access-blocks.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE"

log_lines() { wc -l <"$LOG_FILE" | tr -d ' '; }

assert_log_grew() {
	local name="$1" before="$2" after="$3" pattern="$4"
	if [ "$after" -gt "$before" ] && tail -1 "$LOG_FILE" | grep -qE "$pattern"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        before=%s after=%s last_line=%s\n' \
			"$name" "$before" "$after" "$(tail -1 "$LOG_FILE" 2>/dev/null)"
		FAIL=$((FAIL + 1))
	fi
}

assert_log_unchanged() {
	local name="$1" before="$2" after="$3"
	if [ "$after" -eq "$before" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        before=%s after=%s\n' "$name" "$before" "$after"
		FAIL=$((FAIL + 1))
	fi
}

echo "# 1. Destructive commands blocked"
assert_block "1.1 bq rm" "bq rm -f mydataset.mytable" "BLOCK"
assert_block "1.2 gcloud delete" "gcloud projects delete my-project" "BLOCK"
assert_block "1.3 gcloud set-iam-policy" "gcloud projects set-iam-policy p policy.json" "BLOCK"
assert_block "1.4 uv cache clean" "uv cache clean" "BLOCK"
assert_block "1.5 uv publish" "uv publish" "BLOCK"

echo "# 1b. Token-minting commands blocked"
assert_block "1b.1 gcloud print-access-token" "gcloud auth print-access-token" "BLOCK"
assert_block "1b.2 gcloud print-identity-token" "gcloud auth print-identity-token" "BLOCK"
assert_block "1b.3 aws sts get-session-token" "aws sts get-session-token" "BLOCK"
assert_block "1b.4 aws sts get-federation-token" "aws sts get-federation-token --name x" "BLOCK"
assert_block "1b.5 heroku auth:token" "heroku auth:token" "BLOCK"
assert_block "1b.6 doctl auth token" "doctl auth token" "BLOCK"

echo "# 1c. Token-minting near-misses stay allowed"
assert_allow "1c.1 gcloud auth list" "gcloud auth list"
assert_allow "1c.2 aws sts get-caller-identity" "aws sts get-caller-identity"
assert_allow "1c.3 gcloud config list" "gcloud config list"
assert_allow "1c.4 doctl auth init" "doctl auth init"

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

echo "# 2d. Secrets: expanded credential-store paths blocked"
assert_block "2d.1 netrc" "cat ~/.netrc" "BLOCK"
assert_block "2d.2 gnupg keyring" "cat ~/.gnupg/pubring.kbx" "BLOCK"
assert_block "2d.3 docker config" "cat ~/.docker/config.json" "BLOCK"
assert_block "2d.4 kube config" "cat ~/.kube/config" "BLOCK"
assert_block "2d.5 npmrc" "cat ~/.npmrc" "BLOCK"
assert_block "2d.6 pypirc" "cat ~/.pypirc" "BLOCK"
assert_block "2d.7 gh hosts via jq" "jq . ~/.config/gh/hosts.yml" "BLOCK"

echo "# 2e. Near-miss benign commands stay allowed"
assert_allow "2e.1 docker build" "docker build ."
assert_allow "2e.2 dockerignore reference" "cat .dockerignore"
assert_allow "2e.3 npm install" "npm install"
assert_allow "2e.4 kubectl get pods" "kubectl get pods"
assert_allow "2e.5 commit prose mentions netrc" "git commit -m 'docs: describe .netrc handling'"

echo "# 2c. Secrets: environment dumps blocked"
assert_block "2c.1 bare printenv" "printenv" "BLOCK"
assert_block "2c.2 piped printenv" "printenv | wc -l" "BLOCK"
assert_block "2c.3 printenv secret var" "printenv QUALTRICS_API_KEY" "BLOCK"
assert_block "2c.4 bare env" "env" "BLOCK"
assert_block "2c.5 echo secret var" 'echo $TWILIO_AUTH_TOKEN' "BLOCK"
assert_block "2c.6 printf secret var" 'printf "%s" ${CODERABBIT_API_KEY}' "BLOCK"

echo "# 2f. Language-level environment dumps blocked (data-calibrated, see tests/fixtures/env-dump/)"
assert_block "2f.1 python os.environ bare print" 'python3 -c "import os; print(os.environ)"' "BLOCK"
assert_block "2f.2 python dict(os.environ)" 'python3 -c "import os, json; print(json.dumps(dict(os.environ)))"' "BLOCK"
assert_block "2f.3 node process.env bare" 'node -e "console.log(process.env)"' "BLOCK"
assert_block "2f.4 ruby ENV.to_h" "ruby -e 'puts ENV.to_h'" "BLOCK"
assert_block "2f.5 python os.getenv secret key" "python3 -c \"import os; print(os.getenv('ANTHROPIC_API_KEY'))\"" "BLOCK"
assert_block "2f.6 python os.environ indexed secret key" "python3 -c \"print(os.environ['GITHUB_TOKEN'])\"" "BLOCK"
assert_block "2f.7 node process.env.KEY secret" 'node -e "console.log(process.env.OPENAI_API_KEY)"' "BLOCK"
assert_block "2f.8 ruby ENV indexed secret key" 'ruby -e '"'"'puts ENV["AWS_SECRET_ACCESS_KEY"]'"'"'' "BLOCK"
assert_block "2f.9 python os.environ.items() dump" 'python3 -c "import os; [print(k,v) for k,v in os.environ.items()]"' "BLOCK"

echo "# 2g. Language-level environment access without secret context stays allowed"
assert_allow "2g.1 python os.getcwd" 'python3 -c "import os; print(os.getcwd())"'
assert_allow "2g.2 python getenv non-secret with default" "python3 -c \"import os; p=os.getenv('MY_CONFIG_DIR','/tmp'); print(p)\""
assert_allow "2g.3 plain python script" "python3 script.py"
assert_allow "2g.4 plain node script" "node build.js"
assert_allow "2g.5 python os.path.join" 'python3 -c "import os; print(os.path.join(os.getcwd(), '"'"'data'"'"'))"'
assert_allow "2g.6 node process.version" 'node -e "console.log(process.version)"'
assert_allow "2g.7 ruby RUBY_VERSION" "ruby -e 'puts RUBY_VERSION'"
assert_allow "2g.8 dict literal named ENV_NAME" "python3 -c \"d = {'ENV_NAME': 'prod'}; print(d)\""
assert_allow "2g.9 python getenv non-secret with fallback" "python3 -c \"import os; print(os.getenv('LOG_LEVEL', 'info'))\""
assert_allow "2g.10 script flag named --env" "python3 analyze.py --env production"

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

echo "# 6. Secret-access block logging"
BEFORE=$(log_lines)
run_guard "cat ~/.aws/credentials"
AFTER=$(log_lines)
assert_log_grew "6.1 protected-path block appends a log line" "$BEFORE" "$AFTER" $'\ttest\tbash-guard:protected-path\t'

BEFORE=$(log_lines)
run_guard "printenv"
AFTER=$(log_lines)
assert_log_grew "6.2 env-dump block appends a log line" "$BEFORE" "$AFTER" $'\ttest\tbash-guard:env-dump\t'

BEFORE=$(log_lines)
run_guard "git status"
AFTER=$(log_lines)
assert_log_unchanged "6.3 benign allowed command appends no log line" "$BEFORE" "$AFTER"

echo
echo "──────────────────────────────────────────────"
echo "test-bash-guard: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
