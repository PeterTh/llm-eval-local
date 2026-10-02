# `cholesky_claude-opus-5-cc-medium_omp_r3`

Date: 2026-10-02

## Scope

OpenMP Cholesky, N=4,992. The median is 58 ms, followed by Opus r2 at 65 ms and
r4 at 68 ms.

## Finding

The implementation uses two-level left-looking blocking: 32-wide inner panels
inside 128-wide outer panels. Packed row data feeds a 6×8 AVX2 update kernel, and
partial dot products survive across inner panels. Cyclic row ownership distributes
the shrinking trailing work among the threads.

## Close-group comparison

Opus r2 instead uses one level of 64-wide panels and a 4×8 register kernel.
The winner's 57–60 ms samples are separated from r2's 64–65 ms, so the 10.8% lead
is meaningful in this group. The extra blocking and retained partial updates offer
a specific locality explanation; neither register shape nor block size has been
isolated experimentally. The
[older Sol review](cholesky_gpt-5.6-sol-xhigh_omp_r2.md) provides the broader blocked
factorization context.

## Correctness and timing

Retained validation passed. The factorization workspace, dependent panel work and
completion of the parallel region are included. No NUMA-local allocation advantage
is inferred under the campaign's interleaved memory policy.

## Interpretation

A distinct cache-blocking refinement of the same factorization, with a moderate,
consistently observed lead over its nearest implementation peers.
