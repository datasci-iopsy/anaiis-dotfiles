#!/usr/bin/env bash
# ensure-repo-hooks.sh -- silently install the repo hooks in the current repo
#
# Triggered by UserPromptSubmit. Exits 0 always (non-blocking).
# No output on success -- zero context cost.
#
# Checks both dispatcher hooks, not just pre-commit: every repo on a dev
# machine already carried pre-commit when pre-push was introduced, so an
# early exit on the pre-commit marker alone would mean no existing repo ever
# received the pre-push hook.

set -euo pipefail

repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

hooks="$repo/.git/hooks"

# Already wired up -- nothing to do
if grep -qF -- 'repo-pre-commit.sh' "$hooks/pre-commit" 2>/dev/null \
	&& grep -qF -- 'repo-pre-push.sh' "$hooks/pre-push" 2>/dev/null; then
	exit 0
fi

# Install silently; warn to stderr on failure
if ! (cd "$repo" && bash "$HOME/.claude/scripts/install-repo-hooks.sh" >/dev/null 2>&1); then
	echo "[hooks] Failed to install repo hooks in $repo" >&2
fi

exit 0
