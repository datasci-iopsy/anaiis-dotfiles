#!/usr/bin/env bash
# evals/ponytail/loc.sh -- lines of code each eval run added, joined with the
# run's cost, duration, turns and grader results.
#
# `claude plugin eval --json` reports scores and cost but not code size. With
# --keep-temp each run's workspace survives at <kept>/sealed/home/cwd, and the
# run's tracePath (<kept>/out/trace.jsonl) names the kept directory. This
# script rebuilds the case's seed with its scaffold.sh in a temp dir and
# counts the lines the agent added as `diff -rN` additions, so no git command
# ever runs inside a kept directory (the harness warns against that).
#
#   bash evals/ponytail/loc.sh <aggregate.json> [out.csv]
#   bash evals/ponytail/loc.sh --selftest
#
# CSV columns: case,arm,run,loc_added,files_added,cost_usd,duration_s,turns,score,passed,graders,kept_root

set -eu

REPO_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
CASES_DIR="$REPO_DIR/evals/ponytail/evals"

# Lines present in work_dir and absent from seed_dir, every file, .git excluded.
added_lines() {
	local seed_dir="$1" work_dir="$2"
	diff -rN -x .git "$seed_dir" "$work_dir" 2>/dev/null | grep -c '^> ' || true
}

# Files present in work_dir and absent from seed_dir, .git excluded.
added_files() {
	local seed_dir="$1" work_dir="$2"
	diff -rq -x .git "$seed_dir" "$work_dir" 2>/dev/null | grep -c "^Only in $work_dir" || true
}

selftest() {
	local tmp seed k1 k2 l1 l2 f1 pass=0 fail=0
	tmp="$(mktemp -d)"
	# Expand now on purpose: a local is out of scope when the EXIT trap runs.
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" EXIT
	seed="$tmp/seed"
	mkdir -p "$seed/sub" "$tmp/k1/sealed/home/cwd" "$tmp/k2/sealed/home/cwd"
	printf 'a\nb\nc\n' >"$seed/sub/f.txt"
	k1="$tmp/k1/sealed/home/cwd"
	k2="$tmp/k2/sealed/home/cwd"
	cp -R "$seed/." "$k1/"
	cp -R "$seed/." "$k2/"
	printf 'd\ne\nf\n' >>"$k1/sub/f.txt"
	seq 1 10 >"$k2/new.txt"
	l1="$(added_lines "$seed" "$k1")"
	l2="$(added_lines "$seed" "$k2")"
	f1="$(added_files "$seed" "$k2")"
	for check in "3 lines appended to an existing file:3:$l1" "10 lines in a new file:10:$l2" "one new file counted:1:$f1"; do
		IFS=: read -r name want got <<<"$check"
		if [ "$want" = "$got" ]; then
			printf '  PASS  %s\n' "$name"
			pass=$((pass + 1))
		else
			printf '  FAIL  %s (expected %s, got %s)\n' "$name" "$want" "$got"
			fail=$((fail + 1))
		fi
	done
	echo "loc.sh selftest: $pass passed, $fail failed"
	[ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--selftest" ]; then
	selftest
	exit $?
fi

JSON="${1:?usage: loc.sh <aggregate.json> [out.csv] | --selftest}"
OUT="${2:-${JSON%.json}.loc.csv}"
command -v jq >/dev/null || {
	echo "jq required" >&2
	exit 1
}

SEEDS="$(mktemp -d)"
trap 'rm -rf "$SEEDS"' EXIT

seed_for() {
	local case="$1" dir="$SEEDS/$1"
	if [ ! -d "$dir" ]; then
		mkdir -p "$dir"
		(cd "$dir" && HOME="$SEEDS" bash "$CASES_DIR/$case/scaffold.sh" >/dev/null 2>&1)
	fi
	printf '%s' "$dir"
}

echo "case,arm,run,loc_added,files_added,cost_usd,duration_s,turns,score,passed,graders,kept_root" >"$OUT"
missing=0
while IFS=$'\t' read -r case arm run trace cost secs turns score passed graders; do
	root="$(dirname "$(dirname "$trace")")"
	cwd="$root/sealed/home/cwd"
	chmod 700 "$root" "$root/sealed" 2>/dev/null || true
	if [ ! -d "$cwd" ]; then
		echo "missing workspace for $case/$arm/$run: $cwd" >&2
		missing=$((missing + 1))
		continue
	fi
	seed="$(seed_for "$case")"
	printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
		"$case" "$arm" "$run" "$(added_lines "$seed" "$cwd")" "$(added_files "$seed" "$cwd")" \
		"$cost" "$secs" "$turns" "$score" "$passed" "$graders" "$root" >>"$OUT"
done < <(jq -r '
	.cases[] as $c
	| $c.arms | to_entries[] | .key as $arm
	| .value | to_entries[]
	| [$c.name, $arm, (.key + 1), (.value.tracePath // ""), (.value.costUsd // 0),
	   (.value.durationSeconds // 0), (.value.turns // 0), (.value.score // 0),
	   (.value.passed // false),
	   ([.value.graders[]? | "\(.name)=\(.passed)"] | join(";"))]
	| @tsv' "$JSON")

echo "wrote $OUT ($(($(wc -l <"$OUT") - 1)) rows)"
# Unequal run counts would skew the arm comparison, so an incomplete CSV is an error.
[ "$missing" -eq 0 ] || {
	echo "$missing run(s) had no kept workspace; rerun the suite with --keep-temp" >&2
	exit 1
}
