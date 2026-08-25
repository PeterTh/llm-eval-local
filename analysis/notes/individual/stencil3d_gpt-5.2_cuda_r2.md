# `stencil3d_gpt-5.2_cuda_r2`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place CUDA result in the `stencil3d` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 512-cubed grid
for 451 iterations. Its times are 1721, 1717, 1715, 1715, and 1726 ms, giving a
1717 ms median. The runner-up median is 1718.186 ms, and two more results have medians
of 1719 and 1720 ms.

## Finding

The implementation uses a direct global-memory seven-point Jacobi kernel with a
32 x 4 x 2 thread block. X is the contiguous dimension, so each warp accesses
adjacent cells. One thread handles one cell, including invariant boundary copying,
and two complete grids are swapped after every launch. Compact 32-bit indexing keeps
address arithmetic modest for this known domain size.

This simple kernel is already close to the attainable memory-bandwidth limit. It
avoids shared-memory loading and synchronization that would add work to a stencil
with naturally coalesced adjacent reads.

## Close-group comparison

The 1718.186 ms runner-up uses the same direct global-memory Jacobi algorithm but an
8 x 8 x 4 block and wider index arithmetic. Other members of the 1717–1720 ms group
return to a 32 x 4 x 2-like shape. Thus the close group includes different block
geometries reaching effectively the same bandwidth ceiling, rather than one unique
winning launch configuration.

The gap between the first two medians is 0.07%, and all four leading sample ranges
overlap substantially. Their precise rank ordering has no practical significance.
The useful observation is that multiple uncomplicated, coalesced global-memory
kernels converge on the same performance.

## Correctness and timing validity

Every interior cell is updated in all 451 iterations, boundaries are preserved, and
ping-pong grids maintain Jacobi semantics. CUDA event timing encloses all launches
and records their completion. Retained internal validation and external output
comparison passed.

## Interpretation

This is a statistical first place in a four-way tie. It is evidence for the robust
direct-kernel solution shape, not for a meaningful performance advantage of this
particular run.

## Non-decisions

- No generated source or benchmark result is changed.
- No new tuning result replaces the retained score.
