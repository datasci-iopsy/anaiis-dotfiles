---
name: r-conventions
description: R conventions, vectorization over for-loops, vapply over sapply, pre-allocate when looping is unavoidable, Rcpp for sequential-dependent work
---

# R Programming Conventions

**Default to vectorization over for-loops.** R's built-in vectorized operations run in compiled C/Fortran and are substantially faster than R-level loops at any meaningful data size.

**Vectorization preference hierarchy (highest to lowest):**
1. Built-in vectorized functions: `+`, `*`, `sqrt()`, `sum()`, `rowSums()`, `colMeans()`, `paste0()`, etc.
2. `lapply()` / `vapply()` over lists — these dispatch via C, not R-level loops. Prefer `vapply()` over `sapply()` in performance-sensitive code (pre-specified output type, faster).
3. Pre-allocated for-loop when vectorization is impossible: always initialize output before the loop (`out <- numeric(length(x))`), never grow inside the loop.
4. Rcpp for sequential-dependent or compute-intensive logic that exceeds R-level vectorization.

**Do NOT use a for-loop when:** the operation is element-wise arithmetic, a math function, or a simple transformation on a vector — use the vectorized built-in instead.

**Use a for-loop (or Rcpp) when:**
- Each iteration depends on the previous result (sequential dependency — vectorization is structurally impossible).
- Early exit via `break` or `next` is needed (vectorized operations evaluate all elements).
- Multi-branch conditional logic per row is complex enough that nested `ifelse()` is harder to read and debug than an explicit loop.

**Avoid `apply()` on data frames.** It coerces to matrix and uses an R-level loop internally. Use `lapply()`, `vapply()`, or column-wise vectorized functions instead. `rowSums()` / `colMeans()` are faster than `apply(df, 1/2, sum/mean)`.

**Profile before optimizing.** For small `n` (< ~1,000) or when each iteration is expensive (model fit, I/O), the loop vs. vectorization distinction is negligible. Don't vectorize for its own sake when correctness and readability are clearer in a loop.

**Style** is enforced by `~/.lintr` (tidyverse rules + native `|>` pipe). Run `lintr::lint_dir()` to check. The pre-commit hook catches violations before they reach a commit.
