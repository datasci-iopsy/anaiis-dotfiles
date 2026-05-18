---
name: testing
description: Test-intent discipline: tests must encode why behavior matters, not just what it does; fail-to-fail check required
---

# Testing Discipline

## Tests verify intent, not just behavior

Every test must encode *why* the behavior matters, not just *what* it does. A test that passes regardless of whether the business logic is correct is not a test; it is noise that creates false confidence.

The fail-to-fail check: before accepting a test as valid, verify that it would actually fail if the thing it is guarding broke. If you cannot construct a scenario where the test fails, the test is wrong.

## Failure modes to avoid

- **Hardcoded-return tests.** A function that returns a constant will pass any test that only checks the return type or a fixed value. The test must be parameterized over inputs that would reveal wrong outputs.
- **Tautological assertions.** `expect(result).toBeDefined()` or `expect(result).not.toBeNull()` does not verify correctness, only that something was returned.
- **Mocks that never fail.** A mock that always succeeds hides whether the real integration would succeed. Write at least one test that exercises the path a real failure would take.

## R (testthat / assertthat)

```r
# Wrong: only checks structure, not correctness
test_that("compute_score returns a numeric", {
    expect_type(compute_score(items), "double")
})

# Right: checks output against known input
test_that("compute_score returns mean of non-NA items", {
    expect_equal(compute_score(c(1, 2, NA, 4)), 2.333, tolerance = 0.001)
})
```

Use `vapply` in test helpers that apply checks across a list; `expect_*` functions are vectorized over a single assertion but not a list.

## Python (pytest)

```python
# Wrong: only checks type
def test_score_returns_float(items):
    assert isinstance(compute_score(items), float)

# Right: parameterized over inputs with known outputs
@pytest.mark.parametrize("items,expected", [
    ([1, 2, None, 4], 2.333),
    ([0, 0, 0], 0.0),
])
def test_compute_score(items, expected):
    assert compute_score(items) == pytest.approx(expected, abs=1e-3)
```

See also: `rules/behavioral.md` rule 4 (define success criteria, loop until verified).
