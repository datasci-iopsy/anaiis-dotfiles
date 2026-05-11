"""
Validate a dashboard.config.json manifest and optionally check that
index.html contains the required chart mount divs.

Usage:
    uv run python validate_manifest.py dashboard.config.json
    uv run python validate_manifest.py dashboard.config.json --check-mounts index.html
"""

import argparse
import json
import re
import sys
from pathlib import Path

REQUIRED_CHART_FIELDS = {"id", "title", "render", "fig_builder", "data_source"}
REQUIRED_DATA_SOURCE_FIELDS = {"kind", "query"}
VALID_KINDS = {"bq", "duckdb", "file"}
VALID_RENDERS = {"plotly", "ggplot2"}


def validate_schema(config: dict) -> list[str]:
    errors: list[str] = []

    for field in ("title", "audience", "narrative_arc", "charts"):
        if field not in config:
            errors.append(f"missing top-level field: '{field}'")

    charts = config.get("charts", [])
    if not isinstance(charts, list) or len(charts) == 0:
        errors.append("'charts' must be a non-empty list")
        return errors

    ids_seen: set[str] = set()
    for i, chart in enumerate(charts):
        prefix = f"charts[{i}]"
        for field in REQUIRED_CHART_FIELDS:
            if field not in chart:
                errors.append(f"{prefix}: missing required field '{field}'")

        cid = chart.get("id", "")
        if cid in ids_seen:
            errors.append(f"{prefix}: duplicate chart id '{cid}'")
        if cid:
            ids_seen.add(cid)

        render = chart.get("render", "")
        if render not in VALID_RENDERS:
            errors.append(
                f"{prefix} id='{cid}': render must be one of {VALID_RENDERS}, got '{render}'"
            )

        ds = chart.get("data_source", {})
        if not isinstance(ds, dict):
            errors.append(f"{prefix} id='{cid}': data_source must be an object")
        else:
            for f in REQUIRED_DATA_SOURCE_FIELDS:
                if f not in ds:
                    errors.append(f"{prefix} id='{cid}': data_source missing '{f}'")
            kind = ds.get("kind", "")
            if kind not in VALID_KINDS:
                errors.append(
                    f"{prefix} id='{cid}': data_source.kind must be one of {VALID_KINDS}, got '{kind}'"
                )

    return errors


def check_mounts(config: dict, html_path: Path) -> list[str]:
    errors: list[str] = []
    html = html_path.read_text()
    for chart in config.get("charts", []):
        cid = chart.get("id", "")
        pattern = rf'id=["\']chart-{re.escape(cid)}["\']'
        if not re.search(pattern, html):
            errors.append(
                f"manifest chart '{cid}' has no mount div (id=\"chart-{cid}\") in {html_path}"
            )
    return errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", help="Path to dashboard.config.json")
    parser.add_argument(
        "--check-mounts",
        metavar="HTML",
        help="Also verify mount divs in this HTML file",
    )
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    if not manifest_path.exists():
        print(f"ERROR: manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(1)

    try:
        config = json.loads(manifest_path.read_text())
    except json.JSONDecodeError as exc:
        print(f"ERROR: manifest is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(1)

    errors = validate_schema(config)

    if args.check_mounts:
        html_path = Path(args.check_mounts)
        if not html_path.exists():
            errors.append(f"HTML file not found for mount check: {html_path}")
        else:
            errors.extend(check_mounts(config, html_path))

    if errors:
        print("FAIL: manifest validation errors:")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)

    chart_count = len(config.get("charts", []))
    mode = " (with mount check)" if args.check_mounts else ""
    print(f"OK: manifest valid{mode} -- {chart_count} chart(s)")


if __name__ == "__main__":
    main()
