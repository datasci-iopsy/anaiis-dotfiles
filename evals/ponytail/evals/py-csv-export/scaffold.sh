#!/usr/bin/env bash
# Seed workspace for py-csv-export. Runs in the empty eval workspace before Claude starts.
set -eu
cat >export.py <<'EOF'
"""Export survey records to a file."""

import argparse
import json
from pathlib import Path


def load_records() -> list[dict]:
    return [
        {"id": 1, "group": "a", "score": 4.0},
        {"id": 2, "group": "a", "score": 3.5},
        {"id": 3, "group": "b", "score": 5.0},
    ]


def write_json(records: list[dict], out: Path) -> None:
    out.write_text(json.dumps(records, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("records.json"))
    args = parser.parse_args()
    write_json(load_records(), args.out)


if __name__ == "__main__":
    main()
EOF
printf '[project]\nname = "export"\nversion = "0.1.0"\nrequires-python = ">=3.12"\ndependencies = []\n' >pyproject.toml
git init -q
git add -A
git -c user.name=eval -c user.email=eval@local commit -q -m base
