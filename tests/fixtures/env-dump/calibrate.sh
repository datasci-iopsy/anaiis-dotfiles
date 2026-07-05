#!/usr/bin/env bash
# calibrate.sh: empirical calibration for the language-level env-dump block
# added to bash-guard.sh (secret-tier hardening, Phase 4).
#
# Runs two candidate regex strategies against a labeled corpus of
# malicious.txt (must block) and benign.txt (must allow) commands, then
# prints a confusion matrix per candidate. Kept in-repo as a record of the
# decision: which candidate was chosen and why.
#
# Usage: bash tests/fixtures/env-dump/calibrate.sh

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MALICIOUS="$DIR/malicious.txt"
BENIGN="$DIR/benign.txt"

# Candidate A: narrowest. Blocks only full/untargeted environment dumps.
candidate_a() {
	local cmd="$1"
	printf '%s' "$cmd" | grep -qE 'os\.environ\)' && return 0
	printf '%s' "$cmd" | grep -qE 'os\.environ\.(items|keys|values)\(\)' && return 0
	printf '%s' "$cmd" | grep -qE 'process\.env\)' && return 0
	printf '%s' "$cmd" | grep -qE '\bENV\.(to_h|inspect)\b' && return 0
	printf '%s' "$cmd" | grep -qE '^[[:space:]]*(env|printenv)[[:space:]]*\|' && return 0
	return 1
}

# Candidate B: A, plus targeted getenv/index access when co-occurring with a
# secret-shaped variable name (TOKEN/SECRET/API_?KEY/PASSWORD).
candidate_b() {
	local cmd="$1"
	candidate_a "$cmd" && return 0
	if printf '%s' "$cmd" | grep -qE '(os\.getenv|os\.environ\[|process\.env\.|ENV\[)'; then
		printf '%s' "$cmd" | grep -qiE '(TOKEN|SECRET|API_?KEY|PASSWORD)' && return 0
	fi
	return 1
}

run_matrix() {
	local name="$1" fn="$2"
	local tp=0 fn_count=0 tn=0 fp=0

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		if "$fn" "$line"; then
			tp=$((tp + 1))
		else
			fn_count=$((fn_count + 1))
			echo "    MISSED (false negative): $line"
		fi
	done <"$MALICIOUS"

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		if "$fn" "$line"; then
			fp=$((fp + 1))
			echo "    OVER-BLOCKED (false positive): $line"
		else
			tn=$((tn + 1))
		fi
	done <"$BENIGN"

	echo "  $name: TP=$tp FN=$fn_count TN=$tn FP=$fp"
}

echo "=== Candidate A (narrowest: full-dump idioms only) ==="
run_matrix "Candidate A" candidate_a

echo
echo "=== Candidate B (A + secret-context getenv/index access) ==="
run_matrix "Candidate B" candidate_b
