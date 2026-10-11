# `qtclustering_gpt-6.1-sol-medium_mpi_r3`

Date: 2026-10-11

## Scope

MPI QT clustering, 4,000 points on 128 ranks. The median is 8 ms, against
9 ms for the previous leader and the next two Sol 6.1 results.

## Finding

Seeds are distributed cyclically. A sparse threshold-neighbor structure limits
candidate searches, and each candidate incrementally maintains its maximum
distance to the growing cluster. Stable compaction preserves index tie order.
Cached candidates are rebuilt only when a member is removed; `MPI_MAXLOC`
selects the largest cluster with the smallest seed as tie-breaker, followed by
broadcast of its members. Once only singleton clusters remain, all ranks emit
the remaining indices without one collective per point.

## Close-group comparison

This shares most of the approach described in the
[previous Astra review](qtclustering_gpt-6-astra-medium_mpi_r5.md),
although it does not use that implementation's additional size-bound pruning.
The five times are 8, 7, 11, 10 and 8 ms, overlapping Astra's 9–10 ms and both
nearby Sol results. The source truncates its report to integer milliseconds:
the one-millisecond median difference is too coarse to interpret as a precise
percentage improvement.

## Correctness and timing

Native validation and static timing review passed without correction. Distance
and neighbor preprocessing are inside the timed clustering call. Ranks begin
after a barrier and report the maximum complete elapsed time, including the
distributed cluster selection.

## Interpretation

A close-group result consistent with the existing sparse, cached QT strategy;
neither the measured lead nor a new algorithmic advantage is established.
