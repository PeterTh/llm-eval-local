# `cholesky_gpt-5.6-sol-xhigh_omp_r2`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the first-place outlier in the `cholesky` OpenMP cell for
data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark factored a 4,992 x 4,992 matrix on 128 physical cores.
Its times are 80, 81, 80, 80, and 81 ms, giving a median of 80 ms. The
runner-up has a 105 ms median, so this run is 31.3% faster.

## Finding

The implementation uses long panels to amortize synchronization and a
register-blocked trailing update.

At this matrix size it selects a panel width of 256. One persistent OpenMP team
performs all panels, with a serial diagonal factorization, a parallel
triangular solve, and a dynamically scheduled triangular set of 30 x 30
trailing tiles.

For off-diagonal tiles, a 3 x 3 microkernel accumulates nine dot products
together. Each loaded value from the factored panel feeds three accumulators,
and nine independent reductions hide latency without changing dependencies
between Cholesky panels.

The runner-up uses 64-wide panels, creates a new OpenMP parallel region for
each panel, transposes the panel, and updates the trailing matrix with a
row-oriented kernel. Its shorter panels expose frequent synchronization and
setup even though its local update layout is otherwise effective.

## Controlled evidence

The retained winner reproduced at 80-81 ms and the runner-up at 105 ms under
the benchmark's 128-core placement. A temporary copy of the winner changed
only its large-matrix panel width from 256 to 64. It took 118, 121, and
120 ms.

Thus the long panel alone changes the winner by roughly 1.49x and is sufficient
to explain its 1.31x lead. The runner-up's transposed update partly compensates
for its shorter panel, while the winner combines the longer panel with its
3 x 3 reuse kernel and persistent team.

## Correctness and timing validity

The panel width changes the blocked factorization order but not the Cholesky
dependency structure. Diagonal blocks are completed before their solve and
trailing update; implicit OpenMP barriers separate those phases. Trailing
tiles own disjoint lower-triangular elements.

The retained validation passed internal validation and external output
comparison within the numerical tolerance. Different valid blocking orders
need not produce the same floating-point hash. The timer surrounds the
complete factorization, including all panel synchronizations and final
upper-triangle clearing.

The 80 ms value is short and integer-quantized, but all five retained runs lie
within one millisecond and the controlled panel experiment is substantially
larger than that resolution.

## Interpretation

This is a valid blocking/synchronization outlier. At 4,992 rows, using four
times longer panels reduces the number of global phase boundaries enough to
outweigh the smaller amount of parallel work exposed per panel.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The panel-width variant is explanatory evidence, not replacement benchmark
  data.
