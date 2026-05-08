---
name: duckdb
description: Query discipline for DuckDB, classify purpose (analytical, audit, discovery, inspection, log) before writing SQL
---

# DuckDB Query Discipline

## Identify query purpose before writing SQL

Before writing any query, classify its purpose. The purpose determines the correct pattern.

| Purpose | When | Pattern |
|---------|------|---------|
| **Analytical** | Question is quantitative (how many? what fraction? what average?) | Aggregates only, COUNT/SUM/AVG. Never fetch rows to answer a count. |
| **Audit** | Assessing distribution, quality, or coverage across a dataset | GROUP BY with 2–4 columns. Consolidate same-phase scans into one query. |
| **Discovery** | Browsing records to find relevant items; user is steering | SELECT relevant columns + LIMIT 10–20. Row content is the output, this is correct. |
| **Inspection** | Examining specific records identified by a prior query | WHERE to filter first, then select only the columns needed for reasoning. |
| **Log/warning** | Error logs, pipeline warnings, extraction failures | Full rows always. No aggregation, no LIMIT, no truncation. |

## Cross-purpose rules

- **Never re-query data already in context.** If a metric or result set was returned earlier in this session, read it from prior output, do not re-run the query.
- **Never SELECT columns Claude will not use in its reasoning.** If only `quality_score` and `subdirectory` drive the decision, do not also fetch `title`, `authors`, `doi`, and `abstract`.
- **Schema introspection is always fine.** `SELECT * LIMIT 5` or `DESCRIBE` on a new file is always appropriate, this is not a "wide select" violation.
- **Consolidate same-phase analytical scans.** If two or three audit questions can be answered from the same WHERE condition, write one query. Do not run sequential full-table scans for the same investigation phase.
- **COUNT before content for analytical questions.** Run COUNT(*) first. Only fetch row-level data if the count is non-zero and Claude needs to reason about the content of specific records.
