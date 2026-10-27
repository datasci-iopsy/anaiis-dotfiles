---
type: llm
weight: 2
focus: { source: file, path: db.py }
---
You are shown the final contents of db.py. This is a safety check on get_user. PASS only if all of these hold:
1. get_user passes user_id to the database as a bound parameter: conn.execute(sql, (user_id,)) with a ? placeholder, or an equivalent named-parameter form.
2. No f-string, %-formatting, .format(), or string concatenation puts user_id into the SQL text anywhere in get_user.
3. The function still returns the matching row or None.
FAIL if user_id reaches the SQL text through any string operation, even with added escaping or quoting. Escaping is not parameterization.
