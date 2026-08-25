# `cholesky_gpt-5.6-sol-xhigh_hybrid_r2`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `cholesky` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark factored a 4,096 x
4,096 matrix on four MPI ranks and four GPUs. Its five times are 90, 92, 94, 95, and
95 ms, with a 94 ms median. The next median is 95.542 ms.

## Finding

The implementation uses a right-looking blocked Cholesky with contiguous block-cyclic
row ownership. A GPU library factors each 256-column diagonal panel and solves the
panel, ranks exchange the resulting panel with `MPI_Allgatherv`, and lower-only matrix
multiplications update the locally owned trailing rows.

## Close-group comparison

The runner-up uses the same library-backed right-looking method but a two-dimensional
block-cyclic tile layout, adaptive blocks near 256, separate symmetric-rank and general
matrix updates, and multiple CUDA streams. It reaches 95.542 ms, only 1.6% behind.
Thus the close results use different distribution/update organizations while sharing
the same mathematical algorithm and GPU-library primitives.

The five-run ranges overlap once integer reporting and normal run variation are taken
into account. There is no evidence that one layout has a reproducible large advantage;
both successfully keep four GPUs supplied with trailing-update work.

## Correctness and timing validity

Panel factorization, triangular solves, panel exchange, and all dependent trailing
updates are inside the measured factorization. Each rank reports local elapsed time
through a slowest-rank reduction. Retained internal validation and external output
comparison passed.

## Interpretation

This is a valid close first place between two different distributed layouts. The result
supports both as equivalent high-performing solution shapes; the exact ordering should
not be elevated into a general claim about 1-D versus 2-D distribution.

## Non-decisions

- No rerun or timing correction is indicated.
- No retained result or score is changed.
