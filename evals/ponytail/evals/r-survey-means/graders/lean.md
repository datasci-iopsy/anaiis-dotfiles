---
type: llm
focus: { source: file, path: R/survey.R }
---
You are shown the final contents of R/survey.R. Before the task it held exactly two functions, read_survey(path) and n_respondents(path). Judge only what was added. PASS only if all of these hold:
1. item_means calls the existing read_survey helper rather than calling read.csv or any other reader itself.
2. No package is loaded or referenced (no library(), require(), or pkg:: call).
3. No helper function, S3 class or method, option argument, or configuration object was added beyond item_means itself.
4. The body of item_means is short: a column selection plus one vectorized mean call, or an equivalent of similar size. A for loop that grows a result, manual per-column NA filtering, or a numeric-type check that the task did not ask for counts as over-built.
FAIL if any of these is violated.
