---
type: llm
focus: { source: file, path: R/survey.R }
---
You are shown the final contents of R/survey.R. Before the task it held two functions, read_survey(path) and n_respondents(path). PASS only if all of these hold:
1. A function named item_means exists and takes a path argument.
2. It returns the mean of each of the columns q1 through q5 with NA values ignored (for example colMeans(..., na.rm = TRUE) or an equivalent per-column mean with na.rm = TRUE).
3. The id and group columns are excluded from the result.
4. The file is valid R and read_survey and n_respondents are still present and unchanged.
FAIL if any part is missing or if item_means would error on a CSV with columns id, group, q1, q2, q3, q4, q5 that contains NA values.
