# `stencil3d_claude-opus-5-cc-medium_omp_r1`

Date: 2026-10-02

## Scope

OpenMP 3D stencil, a 512³ grid for 20 steps. The median is 347 ms, followed by
Opus r3 at 372 ms and r5 at 424 ms.

## Finding

A persistent team owns Y/Z regions and vectorizes contiguous X updates. Streaming
stores avoid unnecessary write allocation. Within each assigned region, additional
Y subblocking makes Z traversal reuse a smaller active neighborhood.

## Close-group comparison

Opus r3 already uses a persistent team, fixed tiles and streaming stores; it lacks
the same inner Y-subblock/Z traversal organization. The relevant distinction is
cache reuse inside a common low-traffic stencil loop. The winner's 346–351 ms
range is separated from r3's 370–376 ms, supporting a modest 6.7% median lead.
The [older Sol review](stencil3d_gpt-5.6-sol-xhigh_omp_r5.md) supplies the wider
streaming-stencil context.

## Correctness and timing

Retained validation passed. Boundary values, buffer swaps, store fences and
inter-step barriers are completed in the timed evolution. The campaign uses
NUMA-interleaved memory, so parallel initialization is not evidence of a distinct
NUMA-local placement advantage.

## Interpretation

A credible cache-traversal refinement rather than a new numerical scheme or a
large unexplained throughput discontinuity.
