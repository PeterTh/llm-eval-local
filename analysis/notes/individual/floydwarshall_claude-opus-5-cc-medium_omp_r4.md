# `floydwarshall_claude-opus-5-cc-medium_omp_r4`

Date: 2026-10-02

## Scope

OpenMP Floyd–Warshall, N=8,704. The median is 1,024 ms, versus 1,274 ms for both
Sol 5.6 medium r2 and r4: a 19.6% reduction with nonoverlapping retained ranges.

## Finding

The algorithm processes 64×64 tiles within the row-major distance and path
matrices. Each pivot tile is completed first, then its row and column panels,
then the independent trailing tiles. A trailing update packs its reused distance
panel into contiguous scratch space and keeps small output chunks in registers
while visiting the 64 pivot indices. Branch-free minimum updates maintain path
information alongside distance values.

This reorganizes reuse: a tile's panel data serves many updates while still close
to the cores, instead of repeatedly streaming full matrix rows. Packing the reused
panel avoids large-stride reads in the inner loop. Phase barriers
enforce Floyd–Warshall's dependencies without a whole-team barrier for every scalar
pivot throughout the trailing matrix.

## Close-group comparison

The [previous winner](floydwarshall_gpt-5.6-sol-medium_omp_r2.md) and its near-tied
r4 peer retain the ordered scalar-pivot loop, parallelize rows and vectorize the
column updates. Their medians coincide at 1,274 ms; the new winner's 1,009–1,030 ms
range is clearly separated from both. This is a change in the locality and
synchronization structure, not just a different SIMD spelling inside the same loop.

## Correctness and timing

Retained validation passed. The original graph generator and path updates remain;
the blocked phases preserve the required pivot ordering. Packing and the complete
algorithm are included in the timer, so panel packing is not hidden setup.

## Interpretation

Cache/register reuse and coarser synchronization give a concrete explanation for
this outlier. Their individual contributions were not measured separately; the
evidence supports the combined blocked design rather than a precise causal split.
