#!/usr/bin/env bash
# Seed workspace for sql-param-user. Runs in the empty eval workspace before Claude starts.
set -eu
cat >db.py <<'EOF'
"""SQLite access helpers."""

import sqlite3


def connect(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn


def list_groups(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute("select distinct grp from users order by grp").fetchall()
    return [r["grp"] for r in rows]


def get_user(conn: sqlite3.Connection, user_id: str) -> sqlite3.Row | None:
    sql = f"select id, name, grp from users where id = '{user_id}'"
    return conn.execute(sql).fetchone()
EOF
cat >schema.sql <<'EOF'
create table users (id text primary key, name text not null, grp text not null);
insert into users values ('u1', 'Ada', 'a'), ('u2', 'Bo', 'b');
EOF
git init -q
git add -A
git -c user.name=eval -c user.email=eval@local commit -q -m base
