# `cholesky_claude-opus-5-cc-medium_mpi_r4`

Date: 2026-10-02

## Scope

MPI Cholesky, N=3,072. The median is 31 ms, versus 33 ms for Opus r5 and 45 ms
for Opus r1.

## Finding

A two-dimensional block-cyclic factorization overlaps nonblocking panel transfers
with right-looking updates. Packed AVX2 update kernels operate on small register
tiles while lookahead advances the next panel.

## Close-group comparison

Opus r5 has the same overall organization. The most visible local distinction is
an 8×6 register tile here versus 6×8 in r5, alongside packing and scheduling details.
The median gap is 6.1%, but r5's 29–35 ms range surrounds r4's 31 ms samples.
The evidence supports a fast pair more strongly than a robust ordering between them.

## Correctness and timing

Retained validation passed. Packing, panel communication and the complete
factorization are inside the synchronized interval; the final barrier prevents a
root-only early completion time.

## Interpretation

A small, noisy ordering within a common distributed blocked design. The register
tile shape alone is not established as the cause of the lower median.
