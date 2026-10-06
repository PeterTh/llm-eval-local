# `cholesky_claude-opus-5.5-cc-medium_mpi_r2`

Date: 2026-10-06

## Scope

MPI Cholesky, N=3,072. The median is 28 ms, versus 31 ms for both the previous
Opus 5 winner and Opus 5.5 r5.

## Finding

Ranks own 32-row blocks in a reflected cyclic order, balancing the heavier bottom
rows. Node-shared matrix rows and readiness flags replace same-node panel copies.
Packed updates vectorize across eight independent rows and six columns, retaining
partial sums across panels and batching far-field updates over eight panels.

## Close-group comparison

The [previous winner](cholesky_claude-opus-5-cc-medium_mpi_r4.md) uses a
two-dimensional block-cyclic layout and nonblocking panel transfers. Both are
blocked, overlapped factorizations; shared-row access and the one-dimensional
work distribution distinguish this implementation. Its 28–29 ms range is below
the old winner's five 31 ms samples and r5's 30–32 ms range, though the absolute
difference is just two to three timer ticks.

## Correctness and timing

Retained validation and corrected-source revalidation passed. Ordered partial
updates preserve the factorization dependencies. The synchronized computation is
reported using the corrected maximum-rank elapsed time.

## Interpretation

A small but separated lead at this size. The layout is particularly suited to
the campaign's single-node shared-memory MPI setting; it does not establish the
same advantage across nodes.
