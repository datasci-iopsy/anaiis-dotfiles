#!/usr/bin/env bash
# tests/e2e-nested-session.sh -- end-to-end hook checks in real nested Claude Code sessions.
#
# Each case starts `claude -p` in a temp directory with only the hooks under test loaded
# (--setting-sources project --settings <generated>), then reads the tool calls and tool results
# from stream-json. It never trusts the model's own summary.
#
# Opt-in, because every case spends tokens:
#   E2E=1 bash tests/e2e-nested-session.sh
# Fail-to-fail check: also run every case against the hooks at a git ref and expect the defect:
#   E2E=1 E2E_OLD_REF=<ref> bash tests/e2e-nested-session.sh
# Run a subset of cases (names are the case_* functions without the prefix):
#   E2E=1 E2E_ONLY="rtk_absent guard_words" bash tests/e2e-nested-session.sh
#
# Result per case: PASS, FAIL, or NOT RUN. NOT RUN means the model did not make the expected tool
# call or claude could not run; it is never counted as a pass. WEAK means the old hooks passed a
# case that should expose a defect, so the case does not detect it.

set -u

[ "${E2E:-}" = 1 ] || {
	echo "skip: set E2E=1 to run (spends tokens)"
	exit 0
}
for dep in claude jq git; do
	command -v "$dep" >/dev/null || {
		echo "skip: $dep not on PATH"
		exit 0
	}
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${E2E_MODEL:-haiku}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAKE_HOME="$WORK/fakehome"
mkdir -p "$FAKE_HOME"

PASS=0
FAIL=0
NOTRUN=0
WEAK=0
STREAM=""

# hooks_for <new|old>: prints the directory that holds the hook scripts.
hooks_for() {
	if [ "$1" = new ]; then
		echo "$REPO_DIR/claude/hooks"
		return
	fi
	local d="$WORK/old-hooks" f
	mkdir -p "$d"
	for f in bash-guard.sh post-edit-lint.sh; do
		git -C "$REPO_DIR" show "$E2E_OLD_REF:claude/hooks/$f" >"$d/$f"
	done
	echo "$d"
}

# hooks_settings <hooks-dir> <out>: guard on Bash, formatter on Edit|Write; nothing else loads.
hooks_settings() {
	jq -n --arg g "env HOME=$FAKE_HOME bash $1/bash-guard.sh" --arg f "bash $1/post-edit-lint.sh" \
		'{hooks: {
			PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $g}]}],
			PostToolUse: [{matcher: "Edit|Write", hooks: [{type: "command", command: $f}]}]}}' >"$2"
}

# run_claude <settings> <cwd> <prompt>: sets STREAM. Fails when the session did not finish cleanly.
run_claude() {
	STREAM="$WORK/stream.$RANDOM.jsonl"
	(cd "$2" && claude -p --setting-sources project --settings "$1" --model "$MODEL" \
		--no-session-persistence --allowedTools "Bash,Write,Read,Edit" \
		--output-format stream-json --verbose --include-hook-events "$3" >"$STREAM" 2>/dev/null)
	jq -e 'select(.type == "result" and (.is_error | not))' "$STREAM" >/dev/null 2>&1
}

# result_of <needle>: "is_error<TAB>content" of the tool call whose command or path holds the needle.
result_of() {
	jq -rs --arg k "$1" '
		[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
			| select(((.input.command // .input.file_path // "") | tostring) | contains($k)) | .id] as $ids
		| ([.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
			| select(.tool_use_id as $i | $ids | index($i))] | .[0]) // empty
		| "\(.is_error // false)\t\(.content | tostring | gsub("\n"; " "))"' "$STREAM"
}

# verdict <variant> <case> <PASS|FAIL|NOTRUN> <detail>
verdict() {
	local variant="$1" name="$2" got="$3" detail="$4"
	if [ "$got" = NOTRUN ]; then
		printf '  NOT RUN  %s [%s]: %s\n' "$name" "$variant" "$detail"
		NOTRUN=$((NOTRUN + 1))
	elif [ "$variant" = new ]; then
		if [ "$got" = PASS ]; then
			printf '  PASS  %s\n' "$name"
			PASS=$((PASS + 1))
		else
			printf '  FAIL  %s: %s\n' "$name" "$detail"
			FAIL=$((FAIL + 1))
		fi
	elif [ "$got" = FAIL ]; then
		printf '  PASS  %s [old hooks reproduce the defect: %s]\n' "$name" "$detail"
		PASS=$((PASS + 1))
	else
		printf '  WEAK  %s [old hooks also passed; the case does not detect the defect]\n' "$name"
		WEAK=$((WEAK + 1))
	fi
}

# case_rtk_absent: settings.json must not rewrite or reshape a plain command.
case_rtk_absent() {
	local v="$1" d="$WORK/rtk-$1" s="$WORK/rtk-$1.json" r
	mkdir -p "$d"
	git -C "$d" init -q -b main
	echo one >"$d/a.txt"
	git -C "$d" add a.txt
	git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init
	echo two >>"$d/a.txt"
	echo new >"$d/b.txt"
	if [ "$v" = new ]; then
		jq '{hooks: {PreToolUse: .hooks.PreToolUse, PostToolUse: .hooks.PostToolUse}}' "$REPO_DIR/claude/settings.json" >"$s"
	else
		git -C "$REPO_DIR" show "$E2E_OLD_REF:claude/settings.json" \
			| jq '{hooks: {PreToolUse: .hooks.PreToolUse, PostToolUse: .hooks.PostToolUse}}' >"$s"
	fi
	run_claude "$s" "$d" "Use the Bash tool to run exactly this command and nothing else: git status --short   Then reply done." \
		|| {
			verdict "$v" rtk_absent NOTRUN "claude did not finish"
			return
		}
	r=$(result_of "git status")
	[ -n "$r" ] || {
		verdict "$v" rtk_absent NOTRUN "no git status call"
		return
	}
	if jq -e 'select((.subtype // "") | test("hook")) | select(tostring | test("rtk"; "i"))' "$STREAM" >/dev/null 2>&1; then
		verdict "$v" rtk_absent FAIL "a hook event mentions rtk"
	elif printf '%s' "$r" | grep -q ' M a.txt' && printf '%s' "$r" | grep -q '?? b.txt'; then
		verdict "$v" rtk_absent PASS ""
	else
		verdict "$v" rtk_absent FAIL "git status output is not the raw porcelain form: ${r:0:90}"
	fi
}

# case_guard_words: words that are not paths must not be blocked.
case_guard_words() {
	local v="$1" d="$WORK/gw-$1" s="$WORK/gw-$1.json" n bad="" r
	mkdir -p "$d"
	echo "credentials" >"$d/notes.md"
	hooks_settings "$(hooks_for "$v")" "$s"
	run_claude "$s" "$d" "Run these three shell commands, each as its own Bash tool call, in this order, and nothing else: 1) echo process.env.FOO  2) grep -c credentials notes.md  3) echo gserviceaccount.com   If a command fails or is blocked, still run the next one. Then reply done." \
		|| {
			verdict "$v" guard_words NOTRUN "claude did not finish"
			return
		}
	for n in "process.env.FOO" "grep -c credentials" "gserviceaccount.com"; do
		r=$(result_of "$n")
		[ -n "$r" ] || {
			verdict "$v" guard_words NOTRUN "no call for: $n"
			return
		}
		[ "${r%%$'\t'*}" = false ] || bad="$bad [$n]"
	done
	if [ -z "$bad" ]; then verdict "$v" guard_words PASS ""; else verdict "$v" guard_words FAIL "blocked:$bad"; fi
}

# case_guard_paths: real secrets paths stay blocked, and the message names the matched token.
case_guard_paths() {
	local v="$1" d="$WORK/gp-$1" s="$WORK/gp-$1.json" n bad="" r
	mkdir -p "$d"
	echo "DUMMY=1" >"$d/.env"
	echo "dummy" >"$d/server.key"
	hooks_settings "$(hooks_for "$v")" "$s"
	run_claude "$s" "$d" "Run these two shell commands, each as its own Bash tool call, in this order, and nothing else: 1) cat .env  2) cat server.key   If a command fails or is blocked, still run the next one. Then reply done." \
		|| {
			verdict "$v" guard_paths NOTRUN "claude did not finish"
			return
		}
	for n in "cat .env" "cat server.key"; do
		r=$(result_of "$n")
		[ -n "$r" ] || {
			verdict "$v" guard_paths NOTRUN "no call for: $n"
			return
		}
		if [ "${r%%$'\t'*}" != true ] || ! printf '%s' "$r" | grep -q 'protected secrets path'; then
			bad="$bad [$n not blocked]"
		elif ! printf '%s' "$r" | grep -q 'matched:'; then
			bad="$bad [$n message names no token]"
		fi
	done
	if [ -z "$bad" ]; then verdict "$v" guard_paths PASS ""; else verdict "$v" guard_paths FAIL "$bad"; fi
}

# case_sqlfmt_project: the file's own project config applies, not the session's working directory.
case_sqlfmt_project() {
	local v="$1" d="$WORK/sq-$1" s="$WORK/sq-$1.json" lines
	mkdir -p "$d/proj"
	printf '[tool.sqlfmt]\nline_length = 60\n' >"$d/proj/pyproject.toml"
	hooks_settings "$(hooks_for "$v")" "$s"
	run_claude "$s" "$d" "Use the Write tool to create the file $d/proj/q.sql whose content is exactly this one line: select aaaaaaaaaa, bbbbbbbbbb, cccccccccc, dddddddddd, eeeeeeeeee, ffffffffff from some_table   Then reply done." \
		|| {
			verdict "$v" sqlfmt_project NOTRUN "claude did not finish"
			return
		}
	[ -f "$d/proj/q.sql" ] || {
		verdict "$v" sqlfmt_project NOTRUN "file not written"
		return
	}
	lines=$(wc -l <"$d/proj/q.sql" | tr -d ' ')
	if [ "$lines" -gt 1 ]; then verdict "$v" sqlfmt_project PASS ""; else verdict "$v" sqlfmt_project FAIL "formatted at 120, project says 60 (lines=$lines)"; fi
}

# case_keeps_import: an import that the next edit will use must survive the formatter hook.
case_keeps_import() {
	local v="$1" d="$WORK/im-$1" s="$WORK/im-$1.json"
	mkdir -p "$d"
	hooks_settings "$(hooks_for "$v")" "$s"
	run_claude "$s" "$d" "Use the Write tool to create the file $d/probe.py with exactly these three lines: 'import re', an empty line, 'x = 1'. Do nothing else, then reply done." \
		|| {
			verdict "$v" keeps_import NOTRUN "claude did not finish"
			return
		}
	[ -f "$d/probe.py" ] || {
		verdict "$v" keeps_import NOTRUN "file not written"
		return
	}
	if grep -q '^import re' "$d/probe.py"; then verdict "$v" keeps_import PASS ""; else verdict "$v" keeps_import FAIL "the unused import was removed"; fi
}

run_variant() {
	local c
	echo "== hooks: $1"
	for c in rtk_absent guard_words guard_paths sqlfmt_project keeps_import; do
		case " ${E2E_ONLY:-$c} " in
			*" $c "*) "case_$c" "$1" ;;
		esac
	done
}

run_variant new
[ -z "${E2E_OLD_REF:-}" ] || run_variant old

printf '\ne2e-nested-session: %s passed, %s failed, %s weak, %s not run\n' "$PASS" "$FAIL" "$WEAK" "$NOTRUN"
[ "$FAIL" -eq 0 ] && [ "$WEAK" -eq 0 ]
