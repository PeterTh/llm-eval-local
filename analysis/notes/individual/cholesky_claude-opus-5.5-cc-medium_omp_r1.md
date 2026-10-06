# `cholesky_claude-opus-5.5-cc-medium_omp_r1`

Date: 2026-10-06

## Scope

OpenMP Cholesky, N=4,992. The median is 50 ms, versus 58 ms for the previous
Opus 5 winner and 65 ms for the next result.

## Finding

Threads claim whole left-looking tiles in dependency order. Each keeps two tiles
in flight and advances whichever has its next input ready, avoiding a global
barrier after every panel. An 8×6 vector micro-kernel updates column-major partial
sum tiles; completed factors are packed into otherwise-unused upper-triangle
storage, with explicit prefetching of upcoming operands.

## Close-group comparison

The [previous winner](cholesky_claude-opus-5-cc-medium_omp_r3.md) also retains
partial sums and uses packed vector kernels, but organizes work as cyclic rows
with two-level panel blocking. Register blocking is therefore shared, not the
unique explanation. Per-tile scheduling, two in-flight tasks and storage reuse
offer a more specific distinction.

The 48–51 ms samples are below the old leader's 57–60 ms. The 13.8% median lead
is meaningful relative to this separation, without needing a fixed outlier cutoff.

## Correctness and timing

Retained validation passed. Workspace bookkeeping, dependent tile updates,
unpacking/upper-triangle cleanup and parallel-region completion are timed.
No NUMA-local first-touch advantage is inferred under interleaved campaign memory.

## Interpretation

A distinct scheduling and locality refinement of the blocked factorization.
The measurements support the combined design, not separate speedups for its
prefetching, storage reuse or task scheduler.
