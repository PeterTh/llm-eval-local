# `floydwarshall_claude-opus-5-cc-medium_hybrid_r5`

Date: 2026-10-02

## Scope

Hybrid Floyd–Warshall, N=10,240. The median is 146 ms; Opus r4 follows at 147 ms,
then r2 at 203 ms.

## Finding

Ranks own block rows. Register-blocked 64×64 GPU tiles perform the pivot, panel and
trailing phases; node-shared panel storage and two-stream lookahead overlap the
next pivot's communication with independent updates.

## Close-group comparison

Opus r4 shares that design and additionally narrows communicated panel values with
lossless packing. Their samples overlap almost completely: 145–146 versus
145–147 ms. The large improvement over the
[older Sol result](floydwarshall_gpt-5.6-sol-xhigh_hybrid_r1.md) belongs to this
fast implementation pair, not uniquely to r5. A 0.7% median edge does not establish
that omitting the packing is beneficial.

## Correctness and timing

Retained validation passed. Ordered pivot dependencies are preserved. The corrected
timer covers upload, all pivot phases and downloads, with stream completion and
global synchronization before the maximum-rank report.

## Interpretation

An effectively tied leader of a common blocked, overlapped MPI/GPU design.
