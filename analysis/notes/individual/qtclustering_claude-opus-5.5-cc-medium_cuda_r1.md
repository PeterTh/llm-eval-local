# `qtclustering_claude-opus-5.5-cc-medium_cuda_r1`

Date: 2026-10-06

## Scope

CUDA QT clustering, 7,800 points. All five samples report 24 ms; Opus 5.5 r5
reports 25 ms, and r2/r4 report 30 ms. The previous leader was 43 ms.

## Finding

A uniform spatial grid limits each seed's candidates to nearby cells. A warp
grows a candidate cluster while maintaining maximum distances incrementally.
Stored member lists allow reuse between rounds: removing a point that was never
selected cannot change that seed's greedy choices. Only affected seeds are
scheduled again.

Single-precision distance filters avoid most double-precision work, with
double-precision evaluation for ambiguous updates and minima, including
square-root rounding ties. Device-side selection and marking are issued in
batches, with host completion checks becoming less frequent as work progresses.

## Close-group comparison

R5 also caches member lists and uses filtered distance decisions, but grows
candidates with size-classed blocks and CUDA graphs. The one-tick difference
between 24 and 25 ms does not isolate a benefit from warp granularity or the grid.

The [43 ms Opus 5 winner](qtclustering_claude-opus-5-cc-medium_cuda_r5.md)
already used warp-level growth and filtered precision. Spatial candidate lookup
and more selective reuse distinguish the new family, so the 44.2% improvement
over that result is best read as a group advance rather than r1's unique advantage.

## Correctness and timing

Retained validation passed. The dedicated QT timing review includes grid creation,
distance/neighbor work, allocation, the greedy loop, downloads and host cluster
reconstruction. No required distance preprocessing is excluded; this version
avoids materializing a full distance matrix rather than timing it elsewhere.
The reviewed fallback logic addresses ambiguous floating-point decisions, but
the retained validation is not a proof for every threshold or input distribution.

## Interpretation

A substantial new fast family built around locality and reuse, with an effectively
close 24–25 ms pair. No additional program executions were needed for this review.
