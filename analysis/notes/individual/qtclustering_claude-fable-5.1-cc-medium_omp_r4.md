# `qtclustering_claude-fable-5.1-cc-medium_omp_r4`

Date: 2026-11-08

## Scope

OpenMP QT clustering, 6,200 points. The median is 14 ms, versus 21 ms for the
previous Opus 5 winner and 28 ms for Fable r5.

## Finding

As in the previous winner, a spatial grid limits candidate searches and complete
candidate memberships are cached across rounds. Removing a nonmember cannot
change that candidate's greedy choices, so only actual membership intersections
invalidate the cache.

The hot growth loop differs substantially. It maintains squared maximum
distances in contiguous arrays, fuses distance updates with 64-entry block
minima, and periodically compacts dead candidates. Only blocks capable of tying
the minimum are scanned to choose the next member. Square roots are removed
from the streaming distance loop, but explicitly retained where needed to
preserve the reference's rounded-distance ties and strict threshold boundary.

One persistent OpenMP team owns seeds and their caches across all rounds.
Heavy rounds steal work from per-thread queues; light rounds stay local.
Queues are ordered by a neighborhood-size upper bound, allowing candidates
that cannot match an already achieved cardinality to be skipped.

## Close-group comparison

The [21 ms Opus winner](qtclustering_claude-opus-5-cc-medium_omp_r2.md) already has
the important exact-membership cache. It evaluates square roots in its hot
distance updates and adjusts team size after measuring first-round work. Thus
Fable's 14–15 ms versus Opus's 20–21 ms samples represent an improvement within
an optimized algorithmic family, not a comparison against naive all-pairs QT.

The extra cardinality pruning is an attractive explanation, but a
[paired diagnostic](../2026-11-08-fable51-outlier-probes.json) does not support it
at this input: three samples were 14, 15, 14 ms normally and 14, 14, 14 ms with
only that pruning disabled. The squared-distance/minimum-selection kernels and
persistent scheduling remain plausible contributors; their individual shares
of the 33.3% median reduction are not measured.

## Correctness and timing

Native validation, shape/topology checks and full-array membership comparison
passed. Threshold conversion finds the largest squared value whose rounded
square root is strictly below the threshold. Candidate selection considers the
whole squared-value range that rounds to the same distance and breaks ties by
point ID. Pruning uses a strict cardinality inequality, preserving winning ties.

Coordinate conversion, the grid, neighborhood counts, cache construction and
all clustering rounds are timed. Only generic worker/allocator warm-up precedes
the timer; no distance matrix or candidate computation is moved there. No
timing correction was needed.

## Interpretation

A clear improvement over the established cached-QT group. The evidence points
to a more efficient implementation of that family, not omitted preprocessing;
the targeted test rules out cardinality pruning as the main explanation here.
