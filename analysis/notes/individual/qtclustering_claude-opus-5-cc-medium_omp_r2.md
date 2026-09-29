# `qtclustering_claude-opus-5-cc-medium_omp_r2`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `qtclustering/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 6200`; calibration and resources were not changed for this batch.

The five retained times are 21.0, 20.0, 21.0, 21.0, 21.0 ms, median **21.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/qtclustering_gpt-5.6-sol-xhigh_omp_r3.md), `qtclustering_gpt-5.6-sol-xhigh_omp_r3`, had times 122.0, 128.0, 131.0, 132.0, 133.0 ms and median 131.0 ms. The old/new median ratio is 6.2381x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/qtclustering_claude-opus-5-cc-medium_omp_r2/qtclustering/qtclustering.cpp); file SHA-256 `d44c6b5e1aa13a951e83a93ef7be91e1cf2035682347ae35cbb9352064d8f415`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

This implementation combines three reductions in work: a spatial grid restricts each seed to neighboring cells, incremental maxima avoid rescanning all current cluster members, and cached candidate clusters are only recomputed after a chosen member is removed. A radius bound skips many cache-overlap checks. Per-thread arenas retain members; generation counters invalidate references when arenas are recycled.

A persistent team dynamically distributes dirty seeds. Barriers separate cache inspection, candidate growth, and single-thread winner selection/compaction. The first pass uses the full team; later passes may use fewer threads when synchronization would dominate. The outer timer covers grid construction, caching, all clustering rounds, and team completion.

These mechanisms plausibly explain the 6.24x improvement. Spatial pruning is valid because every cluster member must lie within the threshold of its seed; cache reuse depends on the chosen-member invariant, not on assuming clusters never overlap. At 21 ms the exact speedup is still affected by whole-millisecond output precision. No cache/grid ablation was run.

## Limits and release decision

Correctness-only checks match the unchanged sequential reference at N=1200 and all
four new QT winners agree on complete result blocks and membership hashes at N=4000,
5000, 6200 and 7800. Full-size agreement is supporting evidence, not a reference proof;
the direct sequential N=4000 attempt exceeded its 240-second budget.
[Commands, output and hashes](../2026-09-29-qt-winner-correctness.json) are retained.
No probe timing enters the benchmark dataset.

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
