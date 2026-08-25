# `cholesky_gpt-5.6-sol-xhigh_mpi_r5`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place MPI result in the `cholesky` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark factored a 3,072 x
3,072 matrix on 128 ranks. Its five times are 48.636, 56.582, 55.919, 57.762, and
53.449 ms, giving a 55.919 ms median. The next median is 58 ms.

## Finding

The program implements a true two-dimensional block-cyclic factorization using 32 x 32
tiles on a Cartesian rank grid. Row and column collectives distribute diagonal and
panel data, while a hand-vectorized eight-wide local kernel updates only owned lower-
triangle tiles. The small tiles expose substantial concurrency across 128 ranks.

## Close-group comparison

The runner-up uses a markedly different layout: contiguous one-dimensional row
ownership, a nominal 64-column panel constrained by each rank's small local row count,
broadcast diagonal data, and an all-gathered panel before local updates. It was also a
timing-corrected program, so its 58 ms value represents slowest-rank timing.

The two layouts are within about 3.6%, and the winner's own samples span more than that
margin. They are different distributed approaches reaching similar performance at an
unusually small 24 rows per rank. The 2-D tiled scheme plausibly benefits from cache-
resident updates and more balanced communication, but the measured first-place margin
is not statistically decisive.

## Correctness and timing validity

The factorization respects panel dependencies and computes the complete lower factor.
Timing begins from a rank barrier and reports `MPI_MAX`; validation and output work are
outside it. Retained internal validation and external output comparison passed.

## Interpretation

This is a valid close result between genuinely different MPI decompositions. It shows
that both fine-grained 2-D tiling and a simpler 1-D panel method can be competitive;
the exact winner is sensitive to run variation.

## Non-decisions

- No additional timing correction is proposed.
- No benchmark value or score is changed.
