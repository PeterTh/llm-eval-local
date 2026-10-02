# `matmul_claude-opus-5-cc-medium_mpi_r2`

Date: 2026-10-02

## Scope

MPI matrix multiplication, N=6,144. The median is 156 ms, versus 234 ms for Opus r1
and 243 ms for Opus r5. The nearest-peer gap is one third of its runtime.

## Finding

A two-dimensional process grid assigns disjoint output rectangles. Each rank
generates the required A rows and B columns locally before timing, so the timed
product needs no panel broadcasts. It still evaluates every term in each assigned
dot product; it does not substitute an analytic answer for the generated matrices.

The local kernel packs aligned panels and uses explicit AVX2/FMA intrinsics with
a 6×8 register tile. Its cache blocks are 144 rows, 256 inner-dimension entries and
512 columns, with explicit prefetching.

## Close-group comparison

Avoiding timed panel communication helps explain the difference from the older
[SUMMA-based winner](matmul_gpt-5.6-sol-xhigh_mpi_r1.md), at 400 ms. It cannot
explain the entire current lead: Opus r1 also generates its blocks locally and has
no timed panel broadcasts.

That nearest peer uses GNU vector operations for a 6×8 kernel and a 120-row cache
block. Both therefore share the high-level decomposition and register dimensions;
instruction scheduling, packing, prefetching and cache blocking are the visible
remaining differences. Their 154–161 and 232–235 ms ranges are clearly separated,
but source inspection alone does not identify one feature as the cause of 78 ms.

## Correctness and timing

Retained validation passed. The complete local products are timed and combined
with a maximum-rank reduction. Input generation is excluded; necessary local
packing and arithmetic are not. The peer's trailing barrier is a timing-structure
difference, not demonstrated evidence that its gap is measurement error.

## Interpretation

A substantial local-GEMM performance outlier within a shared communication-free
timed design. The reduced communication explains the broader family, while the
precise source of the additional kernel advantage remains unisolated.
