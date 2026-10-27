---
type: llm
focus: { source: file, path: export.py }
---
You are shown the final contents of export.py. Before the task it had load_records, write_json, and a main() with one argparse option, --out. Judge only what was added. PASS only if all of these hold:
1. CSV output uses the standard library csv module (csv.DictWriter or csv.writer). No third-party import appears.
2. No class, registry, dispatch table, or formatter abstraction was introduced. One small function such as write_csv beside write_json, the argparse option, and one branch in main is the expected shape.
3. No options beyond --format were added (no delimiter, encoding, quoting, or similar flags nobody asked for).
4. load_records and write_json are unchanged.
FAIL if any of these is violated.
