# `qtclustering_gpt-6-astra-medium_mpi_r5`

Date: 2026-10-02

## Scope

MPI QT clustering, 4,000 points on 128 ranks. The median is 9 ms; Astra 6 r1, r3
and r4 are all at 10 ms. Opus 5 r5, the previous winner, is at 12 ms.

## Finding

Ranks own seeds cyclically. Each seed starts from a precomputed sparse threshold
neighborhood, maintains maximum distances incrementally, and caches its candidate
membership until a committed cluster removes one of those members. Size bounds
skip candidates that cannot beat the current best. `MPI_MAXLOC` selects the global
winner, whose membership is broadcast. Once the global best has size one, remaining
singletons can be emitted in index order.

## Close-group comparison

Astra r1 has essentially the same design; it edits neighborhood lists as points
are removed, whereas r5 retains them and uses scratch state. Their samples overlap
at 9–10 ms, so the one-millisecond ordering is not a precise 10% advantage.

The [Opus review](../individual/qtclustering_claude-opus-5-cc-medium_mpi_r5.md)
describes similar membership caching, but its rebuilds scan all points to recover
a seed's initial neighborhood. Precomputing sparse neighborhoods is a plausible
reason for the Astra group's modest lead.

## Correctness and timing

Retained validation and timing review passed. Distance/neighborhood preprocessing
is inside the timed clustering call, following a barrier; the reported time is
the maximum across ranks. Distance and index tie-breaking remain explicit. No new
correctness probes were run for this review.

## Interpretation

A compact incremental-clustering group has replaced the previous winner. The group
improvement is more informative than the ordering of its four closely placed runs.
