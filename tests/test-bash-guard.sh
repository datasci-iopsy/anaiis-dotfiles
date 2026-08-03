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
STDERR_TMP=$(mktemp)
trap 'rm -rf "$TEST_HOME" "$STDERR_TMP"' EXIT

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

# Allowed AND a non-blocking informational notice is printed to stderr.
assert_notice() {
	local name="$1" cmd="$2" needle="$3"
	run_guard "$cmd"
	if [ "$RC" -eq 0 ] && printf '%s' "$STDERR" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        exit=%s stderr=%s\n' "$name" "$RC" "$STDERR"
		FAIL=$((FAIL + 1))
	fi
}

# Allowed AND no notice text appears (regression guard for unrelated commands).
assert_no_notice() {
	local name="$1" cmd="$2" needle="$3"
	run_guard "$cmd"
	if [ "$RC" -eq 0 ] && ! printf '%s' "$STDERR" | grep -qF -- "$needle"; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        exit=%s stderr=%s\n' "$name" "$RC" "$STDERR"
		FAIL=$((FAIL + 1))
	fi
}

# run_guard_json <command-string>; sets RC and STDOUT (where a hook's
# permissionDecision JSON lands, unlike the exit-2/stderr block pattern the
# other assert_* helpers check). STDERR_TMP is truncated and re-read each
# call rather than a fresh mktemp per call, matching this script's
# set-up-once-at-top style for TEST_HOME.
run_guard_json() {
	local cmd="$1"
	STDOUT=$(jq -n --arg c "$cmd" '{"session_id":"test","tool_input":{"command":$c}}' \
		| HOME="$TEST_HOME" bash "$GUARD" 2>"$STDERR_TMP")
	RC=$?
	STDERR=$(cat "$STDERR_TMP")
}

# Asserts the hook's stdout permissionDecision JSON matches $want (one of
# allow/ask/deny), or "none" if no decision JSON is expected at all (the
# plain exit-2/stderr-block and plain exit-0/no-output paths both count as
# "none" here).
assert_decision() {
	local name="$1" cmd="$2" want="$3"
	run_guard_json "$cmd"
	local got
	got=$(printf '%s' "$STDOUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)
	[ -z "$got" ] && got="none"
	if [ "$got" = "$want" ]; then
		printf '  PASS  %s\n' "$name"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n        want=%s got=%s exit=%s stdout=%s\n' "$name" "$want" "$got" "$RC" "$STDOUT"
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

echo "# 1d. Unsafe force-push blocked, --force-with-lease stays allowed"
assert_block "1d.1 bare --force" "git push --force" "BLOCK"
assert_block "1d.2 bare --force with remote/branch" "git push --force origin main" "BLOCK"
assert_block "1d.3 short -f" "git push -f" "BLOCK"
assert_block "1d.4 short -f with remote/branch" "git push -f origin feature-branch" "BLOCK"
assert_allow "1d.5 --force-with-lease explicit sha" "git push --force-with-lease=feature-branch:abc123 origin feature-branch"
assert_allow "1d.6 --force-with-lease implicit" "git push --force-with-lease origin feature-branch"
assert_allow "1d.7 plain push unaffected" "git push origin feature-branch"

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

echo "# 2c-key. Bare .key dotfiles blocked, no literal-char false positives"
assert_block "2c-key.1 bare dotfile with tilde slash" 'cat ~/.key' "BLOCK"
assert_block "2c-key.2 bare dotfile after space" 'cat .key' "BLOCK"
assert_allow "2c-key.3 word containing s is not a path separator" "echo skeleton"
assert_allow "2c-key.4 word containing key substring" "echo monkey"

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

echo "# 2h. jq filter referencing .env key is not a path reference"
assert_allow "2h.1 jq dot-env filter, no flags" "jq '.env' ~/.claude/settings.json"
assert_allow "2h.2 jq dot-env filter with -r flag" "jq -r '.env.API_KEY' response.json"
assert_allow "2h.3 jq dot-env filter, double-quoted" 'jq ".env" data.json'
assert_block "2h.4 real .env read alongside an unrelated jq call still blocked" "cat .env | jq '.foo'" "BLOCK"

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

echo "# 3b. uv add/pip install: allowed, non-blocking transparency notice"
assert_notice "3b.1 uv add prints [deps] notice" "uv add requests" "[deps]"
assert_notice "3b.2 uv pip install prints [deps] notice" "uv pip install requests" "[deps]"
assert_no_notice "3b.3 uv sync prints no [deps] notice" "uv sync" "[deps]"
assert_no_notice "3b.4 uv run prints no [deps] notice" "uv run pytest" "[deps]"
assert_no_notice "3b.5 uv remove prints no [deps] notice" "uv remove requests" "[deps]"

echo "# 3c. run_guard_json/assert_decision smoke check (no false positive)"
assert_decision "3c.1 [deps] notice case has no decision JSON" "uv add requests" "none"
assert_decision "3c.2 plain allow case has no decision JSON" "git status" "none"

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
assert_allow "4.11 heredoc -m, single-quoted delimiter, mentions .env" 'git commit -m "$(cat <<'\''EOF'\''
mentions .env as prose, not a real path read
EOF
)"'
assert_allow "4.12 heredoc -m, dash variant <<-, single-quoted delimiter" 'git commit -m "$(cat <<-'\''EOF'\''
covers .ssh and credentials handling
	EOF
)"'

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
assert_block "5.12 heredoc -m, unquoted delimiter, real substitution stays visible" 'git commit -m "$(cat <<EOF
$(cat .env)
EOF
)"' "BLOCK"
assert_block "5.13 heredoc -m, single-quoted delimiter, trailing command after close" 'git commit -m "$(cat <<'\''EOF'\''
safe text
EOF
; cat .env)"' "BLOCK"

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

echo "# 7. Recursive rm: scoped allow/ask instead of a blanket deny"

echo "# 7a. Safe-list allows (silent, no friction)"
assert_decision "7a.1 rm -rf .venv" "rm -rf .venv" "allow"
assert_decision "7a.2 multiple safe operands" "rm -rf node_modules dist build" "allow"
assert_decision "7a.3 broadened spelling: --recursive" "rm --recursive coverage" "allow"
assert_decision "7a.4 broadened spelling: -fR" "rm -fR build" "allow"
assert_decision "7a.5 scratchpad dir (uid + literal scratchpad segment)" \
	"rm -rf /private/tmp/claude-501/-Users-x-project/9db8ed1c-8fd2-4bc5-960b-69b62d39b45c/scratchpad/out" "allow"
assert_decision "7a.6 nested safe subpath" "rm -rf tests/fixtures/dotenv/leftover" "allow"
assert_decision "7a.7 /bin/rm broadened invocation form" "/bin/rm -rf node_modules" "allow"
assert_decision "7a.8 backslash-escaped rm broadened invocation form" '\rm -rf .venv' "allow"
echo "# 7b. Non-safe-list falls to ask, never a silent allow or silent deny"
assert_decision "7b.0 rm after a shell keyword (for-loop do) engages the section, not silently ignored -- for-loop ; is compound syntax the laundering guard correctly can't distinguish from chained commands" \
	'for f in *.jsonl; do rm -rf .venv; done' "ask"
assert_decision "7b.1 traversal escaping tests/fixtures/" "rm -rf tests/fixtures/../../src" "ask"
assert_decision "7b.2 one safe operand, one unsafe: whole command asks" \
	"rm -rf node_modules dist ../src" "ask"
assert_decision "7b.3 compound command: laundering guard" "rm -rf .venv && rm -rf /etcX" "ask"
assert_decision "7b.4 unverifiable operand (shell expansion characters)" 'rm -rf "$HOME/x"' "ask"
assert_decision "7b.5 not on the safe-list at all" "rm -rf /Users/someone/project/notes" "ask"
assert_decision "7b.6 bare tests/fixtures with no subpath asks" "rm -rf tests/fixtures" "ask"
assert_decision "7b.7 zero operands" "rm -rf" "ask"
assert_decision "7b.8 absolute path to an otherwise-safe-named dir" "rm -rf /Users/x/project/node_modules" "ask"
assert_decision "7b.9 scratchpad-looking prefix missing the scratchpad segment" \
	"rm -rf /tmp/claude-branch-hygiene-x" "ask"

echo "# 7c. Catastrophic tripwire: hard-deny, on top of (not instead of) ask"
assert_block "7c.1 bare root" "rm -rf /" "catastrophic"
assert_block "7c.2 root glob" "rm -rf /*" "catastrophic"
assert_block "7c.3 bare tilde" "rm -rf ~" "catastrophic"
assert_block "7c.4 literal \$HOME" 'rm -rf $HOME' "catastrophic"
assert_block "7c.5 bare dot" "rm -rf ." "catastrophic"
assert_block "7c.6 bare dot-dot" "rm -rf .." "catastrophic"

echo "# 7d. Placement-ordering regression guard: existing hard-blocks still fire first"
assert_block "7d.1 rm -rf ~/.ssh still exit-2-blocks (protected-path check)" "rm -rf ~/.ssh" "BLOCK"

echo "# 7e. Non-recursive / unrelated rm: section never engages, no decision JSON"
assert_decision "7e.1 non-recursive rm: no JSON" "rm -f single.txt" "none"
assert_allow "7e.2 non-recursive rm: exit 0" "rm -f single.txt"
assert_decision "7e.3 unrelated -R doesn't leak across an operator" "ls -R && rm foo" "none"

echo "# 7f. Message-flag prose immunity (GUARD_STR-based, not raw CMD)"
assert_decision "7f.1 commit message mentioning rm and -rf as prose" \
	'git commit -m "explain the rm -rf recovery flag behavior"' "none"

echo "# 7g. Quoted-prose immunity: rm -rf appearing only as data inside an unrelated command's quoted argument never engages the section (generalizes 7f beyond message-flags). Paired with assert_allow: a plain 'no decision JSON' check alone can't distinguish a correct skip (exit 0) from a worse false-positive hard-block (exit 2) -- this prose deliberately contains a standalone '/' word, which the tripwire's own word-split would catch if the gate wrongly activates."
assert_decision "7g.1 rm -rf mentioned in a log-style function's quoted argument, real compound operator present" \
	'echo "step one" && myfunc "confirmed rm -rf / is dangerous"' "none"
assert_allow "7g.1b same command truly exits 0, not hard-blocked by the tripwire misreading prose" \
	'echo "step one" && myfunc "confirmed rm -rf / is dangerous"'
assert_decision "7g.2 rm -rf embedded as inert test data inside a nested bash -c script, multi-line" \
	$'bash -c \'CMD="rm -rf /"\necho done\'' "none"
assert_allow "7g.2b same command truly exits 0" \
	$'bash -c \'CMD="rm -rf /"\necho done\''
assert_decision "7g.3 rm -rf inside a single-quoted echo argument, no compound operator at all" \
	"echo 'note: rm -rf is dangerous, never run it unattended'" "none"
assert_allow "7g.3b same command truly exits 0" \
	"echo 'note: rm -rf is dangerous, never run it unattended'"

echo "# 7h. Regression guard: a quoted single-token command name is still a real invocation, not prose -- quoted-prose immunity must never create a new evasion vector"
assert_block "7h.1 quoted bare rm command name still executes for real, tripwire must still fire" '"rm" -rf /' "catastrophic"
assert_decision "7h.2 quoted bare rm command name, non-catastrophic operand, must still ask (never silently allow or silently skip)" \
	'"rm" -rf /Users/someone/project/notes' "ask"

echo "# 7i. Long-flag false-positive guard: an 'r' inside a long GNU-style option name is not a recursive short flag"
assert_decision "7i.1 rm --force: no JSON" "rm --force somefile" "none"
assert_allow "7i.2 rm --force: exit 0" "rm --force somefile"
assert_decision "7i.3 rm --verbose: no JSON" "rm --verbose somefile" "none"
assert_allow "7i.4 rm --verbose: exit 0" "rm --verbose somefile"
assert_decision "7i.5 rm --interactive: no JSON" "rm --interactive somefile" "none"
assert_allow "7i.6 rm --interactive: exit 0" "rm --interactive somefile"
assert_decision "7i.7 regression guard: rm -rf .venv still engages the section" "rm -rf .venv" "allow"

echo
echo "──────────────────────────────────────────────"
echo "test-bash-guard: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
