"""
Render a Plotly figure to a self-contained HTML file using the project template.

Usage:
    uv run python render.py --fig fig.json --title "My Dashboard" --out index.html

The fig argument can be:
  - a JSON file produced by fig.to_json() or fig.write_json()
  - "-" to read from stdin

The output is a standalone HTML file that can be served and verified by web-verify.
"""

import argparse
import json
import sys
from pathlib import Path

TEMPLATE = Path(__file__).parent / "index.html.tmpl"


def main() -> None:
    parser = argparse.ArgumentParser(description="Render Plotly figure to HTML")
    parser.add_argument("--fig", default="-", help="Path to fig JSON or '-' for stdin")
    parser.add_argument("--title", default="Dashboard", help="Page title")
    parser.add_argument("--out", default="index.html", help="Output HTML path")
    args = parser.parse_args()

    if args.fig == "-":
        fig_json = sys.stdin.read()
    else:
        fig_json = Path(args.fig).read_text()

    json.loads(fig_json)

    tmpl = TEMPLATE.read_text()
    html = tmpl.replace("{{TITLE}}", args.title).replace("{{FIGURE_JSON}}", fig_json)

    out = Path(args.out)
    out.write_text(html)
    print(f"wrote {out} ({out.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
