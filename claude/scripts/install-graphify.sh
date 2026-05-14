#!/usr/bin/env bash
# install-graphify.sh
# Provisions an isolated uv-managed Python venv for the vendored graphify submodule.
#
# Lifecycle:
#   venv lives at vendor/graphify-venv/ (gitignored, machine-local)
#   graphify is installed editable from vendor/graphify/ (the submodule)
#   Re-running after a submodule update refreshes the install in-place
#
# To upgrade to a new version:
#   cd vendor/graphify && git fetch && git checkout v<N> && cd ../..
#   bash install.sh
#
# Opt-in: if the submodule was not initialized (git clone without --recurse-submodules),
#   this script prints the remediation command and exits 0 (non-fatal).

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBMODULE="$DOTFILES/vendor/graphify"
VENV="$DOTFILES/vendor/graphify-venv"

echo "=== graphify: vendored skill environment ==="
echo ""

# 1. Check uv is available
if ! command -v uv >/dev/null 2>&1; then
	echo "  SKIP uv not found on PATH"
	echo "       Install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"
	echo "       Then re-run: bash $DOTFILES/install.sh"
	exit 0
fi

# 2. Check submodule is initialized
if [ ! -f "$SUBMODULE/pyproject.toml" ]; then
	echo "  SKIP vendor/graphify submodule not initialized"
	echo "       Run: git -C $DOTFILES submodule update --init vendor/graphify"
	echo "       Then re-run: bash $DOTFILES/install.sh"
	exit 0
fi

# 3. Create venv if missing (pinned to Python 3.12 for reproducibility)
if [ ! -x "$VENV/bin/python" ]; then
	echo "  create $VENV"
	uv venv --python 3.12 "$VENV"
else
	echo "  ok     $VENV (exists)"
fi

# 4. Install or refresh graphify from submodule source (editable)
echo "  install graphify (editable) from vendor/graphify/"
uv pip install --python "$VENV/bin/python" -e "$SUBMODULE" --quiet

# 5. Smoke test: import succeeds, print version via package metadata
VERSION=$("$VENV/bin/python" -c "from importlib.metadata import version; print(version('graphifyy'))")
echo ""
echo "  ok   graphify v${VERSION} -> $(basename "$VENV")/"
echo ""
echo "Done."
