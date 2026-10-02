# `nbody_claude-opus-5-cc-medium_hybrid_r3`

Date: 2026-10-02

## Scope

Hybrid N-body, 50,000 bodies and 30 steps. The median is 853 ms, versus 1,004 ms
for Opus r4, but the winner's samples range widely from 786 to 1,098 ms.

## Finding

CPU and GPU work shares adapt while ranks own disjoint target bodies. The GPU
splits each target's source-body loop into segments, exposing more independent
blocks, then reduces partial forces and integrates. Updated coordinates are
all-gathered before the next step.

## Close-group comparison

Opus r4 also balances CPU and GPU work. Its GPU kernel instead assigns a thread
to a target and visits all source tiles in sequence. Segmenting that long reduction
can improve GPU occupancy, at the cost of partial-force storage and a second kernel.
The winner also performs three coordinate all-gathers where r4 gathers packed
positions once, so not every design difference favors it.

The 15.0% median lead warrants examination, but r4's tight 999–1,014 ms range lies
inside the winner's wider range. This is a promising design difference with variable
observed performance, not a uniformly demonstrated 15% advantage.

## Correctness and timing

Retained tolerance-based validation passed. Force evaluation reads old positions;
updated buffers become the next step's inputs only after completion and gathering.
The corrected maximum-rank interval includes all steps, work splitting, GPU
transfers and position collectives. Final velocity collection for output is outside.

## Interpretation

The segmented GPU reduction is a concrete candidate explanation for the faster
samples. Load balance and variability make the exact median gap less conclusive
than the headline ordering suggests.
