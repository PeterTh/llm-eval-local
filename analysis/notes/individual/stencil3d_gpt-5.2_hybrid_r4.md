# `stencil3d_gpt-5.2_hybrid_r4`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `stencil3d` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 384-cubed grid
for 2,800 iterations on four ranks and four GPUs. Its five times are 2984, 3091,
2856, 2814, and 2873 ms, giving a 2873 ms median. The runner-up median is 2928 ms.

## Finding

The grid is divided into contiguous Z slabs with ghost planes. Each rank uses a
direct coalesced CUDA stencil and pinned host buffers for MPI halo staging. Two CUDA
streams and events overlap the deep-interior kernel with device-to-host transfer,
neighbor exchange, and host-to-device transfer of the two boundary planes; separate
edge work completes the cells that depend on arriving halos.

This is the expected high-performance hybrid shape: a low-surface-area decomposition,
direct local GPU updates, and communication hidden behind independent interior work.

## Close-group comparison

The 2928 ms runner-up uses the same Z-slab decomposition, pinned staged halos,
interior/edge split, direct global-memory stencil, and stream/event overlap. Its
block geometry and precise event orchestration differ, but its overall solution is
the same. A further close result at 3030.878 ms uses the same distributed
decomposition and overlap while introducing a shared-memory X/Y-tiled local stencil;
that is a different local-kernel approach reaching similar overall performance.

The winner and runner-up medians differ by only 1.9%, while their samples range from
2814 to 3091 ms and 2781 to 3051 ms respectively. Even the third result's range
overlaps them. The cell is unusually variable, so the exact first-place ordering is
not statistically meaningful.

## Correctness and timing validity

All local interiors and halo-dependent edge planes are updated in every iteration.
Events enforce the dependencies between communication, edge computation, and buffer
reuse. Reported time uses maximum-rank semantics, so incomplete or faster-rank-only
measurement cannot explain the result. Retained validation passed.

## Interpretation

This is a close-group first place among well-overlapped slab decompositions. Both a
direct local kernel and a shared-memory-tiled variant can reach the group; no unique
winner-specific optimization is established by the retained samples.

## Non-decisions

- No generated source or benchmark result is changed.
- No noisy sample is removed and no score is altered.
