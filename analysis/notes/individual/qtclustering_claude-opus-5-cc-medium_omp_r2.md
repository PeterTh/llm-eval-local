# `qtclustering_claude-opus-5-cc-medium_omp_r2`

Date: 2026-10-02

## Scope

OpenMP QT clustering, 6,200 points. The median is 21 ms, versus 45 ms for Opus r4
and 54 ms for Opus r3.

## Finding

A spatial grid restricts threshold-neighbor searches, and maximum distances are
updated incrementally as candidates grow. The important additional optimization
is retaining complete candidate memberships: only candidates whose members are
removed need rebuilding. A radius bound cheaply rules out distant clusters before
the exact overlap test. Per-thread arenas and generation counters manage this
cache, invalidating entries when storage is recycled.

The team also shrinks after the initial round according to actual distance work,
avoiding the cost of keeping a large team busy with nearly exhausted candidates.

## Close-group comparison

Opus r4 already has the spatial grid and incremental distances, but caches only
candidate sizes. It invalidates candidates when removed points lie anywhere in
their seed's threshold ball, a conservative superset of actual membership overlap,
and regrows the winner to recover its members. Its team sizing is less adaptive.

Avoiding those unnecessary rebuilds is a concrete explanation for a 2.14× median
ratio even against this optimized peer. Samples are tightly separated at 20–21
versus 42–55 ms. The much slower
[older Sol winner](qtclustering_gpt-5.6-sol-xhigh_omp_r3.md) is not the only useful
comparison.

## Correctness and timing

Preprocessing and candidate-cache construction are inside the timer. Retained
validation passed; unchanged memberships remain valid under removal of nonmembers.
The [additional QT checks](../2026-09-29-qt-winner-correctness.json) match the
sequential reference at N=1,200 and all four Claude winners at their benchmark
sizes. Full-size agreement is cross-implementation evidence, not a sequential proof.

## Interpretation

The outlier is chiefly an avoidance-of-recomputation design, not just stronger
OpenMP scaling. Exact cache invalidation distinguishes it from its nearest peers.
