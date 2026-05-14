#!/usr/bin/env bash
# Echo the absolute path to the graphify venv's Python interpreter.
# Usage: PYTHON=$(bash ~/.claude/skills/graphify/scripts/graphify-env.sh)
# Exits 1 with a remediation message if the venv is missing.

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
PY="$DOTFILES/vendor/graphify-venv/bin/python"

if [ ! -x "$PY" ]; then
	echo "graphify venv missing. Run: bash $DOTFILES/install.sh" >&2
	exit 1
fi

echo "$PY"
