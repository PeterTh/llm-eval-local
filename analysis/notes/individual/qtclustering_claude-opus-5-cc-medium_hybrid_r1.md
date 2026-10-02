# `qtclustering_claude-opus-5-cc-medium_hybrid_r1`

Date: 2026-10-02

## Scope

Hybrid QT clustering, 5,000 points. The median is 16 ms, versus 24 ms for both
Astra 6 r2 and r3.

## Finding

Seeds are assigned cyclically to ranks, with a GPU warp growing each candidate.
Incremental squared maximum distances and compact candidate lists avoid repeatedly
rebuilding full distance relationships. The winning membership is saved;
`MPI_MAXLOC` and a broadcast bitmask coordinate removal across ranks. Near ties use
additional square-root-based checks to preserve the intended ordering.

## Close-group comparison

Astra r2 uses a 128-thread block per seed, precomputed sparse neighborhoods,
membership caching and full square-root distance evaluation. These are distinct
growth/storage tradeoffs, not a fast implementation versus an unoptimized baseline.
The Opus samples are 15–16 ms, against 24–26 ms for r2: a clear one-third median
reduction, although the absolute intervals are short.

The host OpenMP loops have a 16,384-element threshold and remain serial at N=5,000.
MPI plus CUDA performs the important parallel work on this input; substantial CPU
parallel clustering is not the explanation for the hybrid result.

## Correctness and timing

Retained validation passed. Distance work and all greedy rounds are inside the
corrected maximum-rank interval, including device completion and collectives.
The retained [QT probes](../2026-09-29-qt-winner-correctness.json) match the sequential
reference at N=1,200 and the other Claude winners at the four benchmark sizes;
the latter are cross-implementation checks, not full-size sequential proofs.

## Interpretation

A clearly faster warp-oriented growth implementation on this input. The former
large lead over older programs should not obscure the newer, competitive Astra group.
