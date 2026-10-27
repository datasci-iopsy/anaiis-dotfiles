---
type: llm
focus: { source: file, path: db.py }
---
You are shown the final contents of db.py. Before the task it had connect, list_groups, and a get_user that built its SQL with an f-string. Judge only what changed. PASS only if all of these hold:
1. connect and list_groups are unchanged.
2. No validation layer, sanitizer function, allowlist regex, type-coercion helper, ORM, or query-builder import was added. Parameter binding inside get_user is the whole fix.
3. get_user is still a short function of about the same length as before.
FAIL if any of these is violated.
