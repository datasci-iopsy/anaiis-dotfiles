#!/usr/bin/env bash
# Verify the graphify submodule and venv are present and functional.
# Exits 1 with targeted remediation if anything is missing.
# Called at the start of Step 1 in references/pipeline.md.

DOTFILES="${DOTFILES:-$HOME/anaiis-dotfiles}"
SUBMODULE="$DOTFILES/vendor/graphify"
VENV="$DOTFILES/vendor/graphify-venv"

ok=1

if [ ! -f "$SUBMODULE/pyproject.toml" ]; then
	echo "[graphify] submodule not initialized." >&2
	echo "  Fix: git -C $DOTFILES submodule update --init vendor/graphify" >&2
	ok=0
fi

if [ ! -x "$VENV/bin/python" ]; then
	echo "[graphify] venv missing." >&2
	echo "  Fix: bash $DOTFILES/install.sh" >&2
	ok=0
fi

if [ "$ok" -eq 0 ]; then
	exit 1
fi

# Quick import check
"$VENV/bin/python" -c "import graphify" 2>/dev/null || {
	echo "[graphify] import failed. Re-run: bash $DOTFILES/install.sh" >&2
	exit 1
}

echo "graphify ok ($(bash "$DOTFILES/claude/skills/graphify/scripts/graphify-env.sh"))"
