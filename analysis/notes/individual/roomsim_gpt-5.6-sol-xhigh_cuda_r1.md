# `roomsim_gpt-5.6-sol-xhigh_cuda_r1`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place CUDA result in the `roomsim` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used 5,120 triangles
and 10,000 time steps. Its five total computation times are 4714, 4738, 4735, 4729,
and 4722 ms, giving a 4729 ms median. The runner-up median is 5840 ms.

## Finding

The implementation keeps all three expensive phases on the GPU and parallelizes
each at a granularity suited to the work:

- Form factors are computed once per unordered triangle pair, then written in both
  directed forms. Sixteen deterministic ray samples are distributed across lanes.
  The convex icosphere geometry also makes third-triangle occlusion impossible for
  a segment joining two surface facets, so no unnecessary octree traversal remains.
- Propagation assigns one block to each receiving triangle and uses warp reductions
  for the weighted sum.
- Cross-correlation assigns one block to each receiver and distributes candidate
  lags across threads, with the two signals cached when shared-memory capacity allows.

The retained phase times show that propagation and correlation dominate, at roughly
2410 and 2320 ms respectively; precomputation is only a few milliseconds.

## Close-group comparison

There is no close leading group: the runner-up is about 23.5% slower. It also exploits
the convexity observation, but computes ordered form-factor pairs with one thread per
pair, uses a shared-memory tree reduction for propagation, and assigns one CUDA
thread to each receiver's entire serial lag search. Its typical propagation and
correlation phases are about 3400 and 2440 ms.

Both implementations therefore use the same physical model and broad GPU-resident
solution, but the winner has materially different and better parallel reductions,
especially in propagation. This is a real kernel-organization advantage rather than
close-group noise.

## Correctness and timing validity

Reciprocal form-factor writes preserve both directed coefficients, all simulation
steps execute, and the complete lag range is searched. Each phase's host timer is
followed by device synchronization before its value is reported; total time is the
sum of those completed phases. Retained validation passed.

## Interpretation

This is a credible structural CUDA win. Its score reflects more complete parallelism
in the dominant reductions, not missing geometry or asynchronously reported work.

## Non-decisions

- No generated source or benchmark result is changed.
- No controlled rerun replaces the retained measurement.
