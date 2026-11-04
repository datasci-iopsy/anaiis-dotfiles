#!/usr/bin/env bash
# Fixture for tests/test-lib-cov.sh. Two branches, one function, one heredoc.
# The test expects nine executable lines. Change this file only together with the test.
set -u
mode="${1:-}"
if [ "$mode" = "a" ]; then
	echo "branch a"
else
	echo "branch b"
fi
helper() {
	echo "helper"
}
cat <<'EOF' >/dev/null
echo not code
EOF
if [ "$mode" = "a" ]; then helper; fi
exit 0
