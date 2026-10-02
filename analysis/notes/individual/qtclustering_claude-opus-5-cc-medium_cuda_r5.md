# `qtclustering_claude-opus-5-cc-medium_cuda_r5`

Date: 2026-10-02

## Scope

CUDA QT clustering, 7,800 points. The median is 43 ms, followed by Opus r1 at
53 ms and r2 at 56 ms.

## Finding

One cooperative kernel executes the greedy outer loop, using grid synchronization
between cluster decisions. A warp grows each seed's candidate, incrementally
maintaining maximum distances and compacting infeasible points. Small candidate
sets stay in shared memory, with a global-memory spill path.

Single precision filters distance decisions using an error window for the
generator's bounded coordinates. Candidates near an ambiguous minimum are checked
against actual members in double precision. This reduces expensive arithmetic
without simply changing every clustering decision to float.

## Close-group comparison

Opus r1 uses a block per seed, precomputed double-precision squared distances and
cached candidate sizes. It already batches rounds with CUDA graphs, so removing
host round trips is not unique to the winner. Warp-level growth, shared candidate
storage and filtered precision distinguish the 41–43 ms result from r1's 53 ms
samples. The 18.9% lead is substantial; the much larger gap from the
[older Sol result](qtclustering_gpt-5.6-sol-xhigh_cuda_r2.md) describes an entire
new fast group, not the isolated benefit of a single cooperative kernel.

## Correctness and timing

The timer includes allocation, preprocessing, the greedy loop, result downloads
and reconstruction. Retained validation passed. Additional
[correctness checks](../2026-09-29-qt-winner-correctness.json) matched the sequential
reference at N=1,200 and matched all four Claude QT winners at N=4,000, 5,000,
6,200 and 7,800. The sequential N=4,000 attempt timed out, so those cross-checks
are not a full-size reference proof. Floating-point filtering still merits that
distinction; source comments alone do not prove every boundary case.

## Interpretation

A credible fast candidate-growth design with a clear lead over already optimized
peers. No ablation assigns separate gains to warp granularity, storage or precision.
