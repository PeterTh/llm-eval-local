# `stencil3d_claude-opus-5.5-cc-medium_cuda_r5`

Date: 2026-10-06

## Scope

CUDA 3D stencil, 512³ cells and 451 iterations. The median is 1,499 ms,
effectively tied with Opus 5.5 r1 at 1,500 ms; r3 follows at 1,511 ms.

## Finding

Each thread marches along a z chunk, keeping adjacent planes' center values in
registers. Boundary copies are fused into the stencil kernel. Division by seven
uses integer significand arithmetic with rounding and an exceptional-value
fallback, rather than a general FP64 divide for every ordinary cell.

## Close-group comparison

R1 also uses register z traversal and the specialized division, but copies
boundaries separately. Its 1,495–1,503 ms samples overlap r5's 1,497–1,503 ms
almost exactly, so fusion cannot be credited with a demonstrated gain here.
The roughly 12.7% improvement over the
[older 1,717 ms winner](stencil3d_gpt-5.2_cuda_r2.md) belongs to the new leading
group; the one-millisecond first-place margin is not meaningful.

## Correctness and timing

Retained validation passed. Summation order and fixed boundaries are preserved.
All 451 iterations finish with device synchronization before the timer stops;
initialization and final host retrieval lie outside that compute interval.

## Interpretation

A fast register-reuse and arithmetic-specialization family, with a practical tie
between its two leading implementations.
