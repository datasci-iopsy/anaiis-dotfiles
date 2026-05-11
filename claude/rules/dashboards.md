# Dashboard Rules

Applies whenever `anaiis-dashboard` is active or whenever Claude generates a browser-rendered page that contains data visualizations for stakeholder audiences.

## 1. Data provenance

Every chart rendered in a dashboard must trace to a query or file in the manifest's `data_source` field. No chart is rendered from data Claude generated without a source. If a user requests a chart with no data source, stop and ask where the data lives before writing any `fig_builder` code.

This extends `rules/citations.md` into the dashboard context: the same "no fabrication" principle that applies to academic citations applies to chart data.

## 2. Manifest discipline

The manifest (`dashboard.config.json`) is written and validated before any chart rendering begins. Claude does not write a `fig_builder` script for a chart that is not in the manifest. If a new chart is needed mid-session, add it to the manifest and re-run `validate_manifest.py` before proceeding to Phase 3.

Rationale: the manifest is the contract between the data layer, the chart layer, and the shell layer. Bypassing it produces dashboards where charts exist in the page but are not tested or tracked.

## 3. Narrative-data alignment

The `description` field on each chart must be derivable from the data after rendering. During Phase 7 acceptance, Claude compares each description to the rendered chart and states "ALIGNED" or flags a mismatch. A mismatch is never silently passed; the user must choose to revise the description or the analysis before the dashboard is declared complete.

This is not an aesthetic rule. A description that claims "metric is increasing" when the chart shows a decline constitutes a data integrity problem, not a wording preference.

## 4. Audience-appropriate language

Before accepting a dashboard as complete, confirm that titles and descriptions are free of internal jargon, unexplained abbreviations, and technical identifiers (table names, column names, model names) that a non-technical stakeholder would not recognize. Rewrite in plain language. The audience field in the manifest should guide the register.

## 5. No inline fabricated data

Data inlined into `<script type="application/json">` blocks in a single-file dashboard must originate from a real query result or file. The `inline_charts.py` helper reads from `artifacts/charts/<id>.fig.json`, which is always produced by a `fig_builder` that read from `data/`. Do not hand-write fig JSON.
