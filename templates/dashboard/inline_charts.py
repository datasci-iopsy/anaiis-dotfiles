"""
Phase 5 helper: convert a multi-file dashboard into a single self-contained HTML.

Reads dashboard.config.json to get chart ids, then for each chart:
  1. Reads artifacts/charts/<id>.fig.json
  2. Injects it as <script type="application/json" id="fig-<id>"> before </body>

Also inlines bootstrap.js (from this script's directory) before </body>.
The data-fig attribute on each .chart-mount is removed (bootstrap reads inline JSON instead).
Plotly CDN script tag is left as-is.

Usage:
    uv run python inline_charts.py --manifest dashboard.config.json --html index.html --out index.html
    uv run python inline_charts.py --manifest dashboard.config.json --html index.html --out dashboard.html
"""

import argparse
import json
import re
import sys
from pathlib import Path

BOOTSTRAP_PATH = Path(__file__).parent / "bootstrap.js"


def inline_charts(manifest_path: Path, html_path: Path, out_path: Path) -> None:
    config = json.loads(manifest_path.read_text())
    charts = config.get("charts", [])
    html = html_path.read_text()

    inject_blocks: list[str] = []

    for chart in charts:
        cid = chart["id"]
        fig_path = Path("artifacts") / "charts" / f"{cid}.fig.json"
        if not fig_path.exists():
            print(f"ERROR: fig not found: {fig_path}", file=sys.stderr)
            sys.exit(1)

        fig_json = fig_path.read_text()
        json.loads(fig_json)

        inject_blocks.append(
            f'<script type="application/json" id="fig-{cid}">{fig_json}</script>'
        )

        html = re.sub(
            rf'(<div[^>]+id=["\']chart-{re.escape(cid)}["\'][^>]*)\s+data-fig=["\'][^"\']*["\']',
            r"\1",
            html,
        )

    bootstrap_js = BOOTSTRAP_PATH.read_text()
    inject_blocks.append(f"<script>\n{bootstrap_js}\n</script>")

    injection = "\n".join(inject_blocks) + "\n"
    if "</body>" in html:
        html = html.replace("</body>", injection + "</body>", 1)
    else:
        html = html + "\n" + injection

    out_path.write_text(html)
    size_kb = out_path.stat().st_size / 1024
    print(f"wrote {out_path} ({size_kb:.1f} KB, {len(charts)} chart(s) inlined)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="dashboard.config.json")
    parser.add_argument("--html", default="index.html")
    parser.add_argument("--out", default="index.html")
    args = parser.parse_args()

    inline_charts(
        manifest_path=Path(args.manifest),
        html_path=Path(args.html),
        out_path=Path(args.out),
    )


if __name__ == "__main__":
    main()
