# `matmul_claude-opus-5-cc-medium_omp_r1`

Date: 2026-10-02

## Scope

OpenMP matrix multiplication, N=8,832. The median is 473 ms, versus 563 ms for
Opus r2 and 574 ms for Opus r3.

## Finding

A fixed two-dimensional thread grid owns output rectangles. Private, cache-line
aligned packed panels feed a 6×8 AVX2/FMA microkernel. Blocking limits the active
working set; B packing is reused according to the thread's assigned rows rather
than materializing one global packed copy of both full matrices.

## Close-group comparison

Opus r2 also has a 6×8 AVX2 kernel, so SIMD and register blocking alone do not
explain the lead. It globally packs the matrices and dynamically schedules output
rectangles, whereas r1 couples private packing to fixed ownership. The distinction
is working-set organization, packing reuse and scheduling.

The winner's 470–484 ms samples are separated from r2's 553–573 ms: a 16.0% median
reduction. This supports a real implementation difference, without establishing
how much comes from each packing or scheduling choice. The
[older Sol review](matmul_gpt-5.6-sol-xhigh_omp_r3.md) provides context for the broader
packed CPU-GEMM family.

## Correctness and timing

Retained validation passed. All rows, columns and inner-dimension terms are
computed, with explicit remainder handling. Per-team workspace preparation,
packing and completion of the multiplication are inside the timed call.

## Interpretation

A substantial improvement in how a conventional vectorized product is partitioned
and fed from memory, rather than a reduction in the mathematical work requested.
