---
type: llm
focus: { source: file, path: export.py }
---
You are shown the final contents of export.py. Before the task it had load_records, write_json, and a main() with an argparse --out option that wrote JSON. PASS only if all of these hold:
1. The CLI accepts --format with the values json and csv, and json is the default.
2. With --format csv the records are written to the --out path as CSV with a header row (id, group, score) and one row per record.
3. The JSON path still works as before.
4. The code is valid Python 3.12 using only the standard library.
FAIL if any part is missing.
