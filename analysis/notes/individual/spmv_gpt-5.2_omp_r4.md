# `spmv_gpt-5.2_omp_r4`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place OpenMP result in the `spmv` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 5,000-row
matrix with 40 nonzeros per row and 50,000 repetitions. Its times are 338, 320, 327,
348, and 328 ms, giving a 328 ms median. The runner-up median is 348.300 ms.

## Finding

The implementation creates one persistent OpenMP team for all 50,000 repetitions.
Each repetition statically partitions rows, vectorizes the inner CSR traversal, and
uses `nowait` to remove the worksharing barrier between repetitions. That omission is
safe here: the matrix and vector are immutable, and every thread writes only the
output rows assigned to it. A later repetition does not consume the preceding output.

Avoiding repeated team creation and 50,000 unnecessary global barriers is the key
structural optimization.

## Close-group comparison

The 348.300 ms runner-up removes the same synchronization cost by manually assigning
each thread a contiguous row range balanced by cumulative nonzeros, then letting that
thread execute all repetitions over its own rows. The next result, at 369.765 ms,
uses almost exactly the winner's persistent-team, static-workshare, `nowait` shape.
These are closely related solutions: they differ in whether ownership is expressed
through OpenMP worksharing or explicit per-thread bounds, not in the sparse algorithm.

The winner's median is 5.8% below the immediate runner, but the five-sample ranges
overlap and both sets are variable. Millisecond integer reporting also limits the
precision of the comparison. The lead is therefore credible as an observed score,
but static inspection does not support a unique algorithmic explanation for the exact
rank within this no-barrier family.

## Correctness and timing validity

Every row and nonzero is processed in each repetition. The missing inter-repetition
barrier cannot create a race because inputs never change and row outputs are exclusive.
The timer encloses the persistent parallel region, so all worker activity finishes
before measurement ends. Retained internal validation and external output comparison
passed.

## Interpretation

The no-barrier persistent-team family has the meaningful advantage. This particular
first place is best described as the fastest noisy sample set within that family,
not as a distinct OpenMP algorithm.

## Non-decisions

- No generated source or benchmark result is changed.
- No sample is removed and no retained median is altered.
