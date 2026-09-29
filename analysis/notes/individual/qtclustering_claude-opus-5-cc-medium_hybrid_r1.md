# `qtclustering_claude-opus-5-cc-medium_hybrid_r1`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `qtclustering/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 5000`; calibration and resources were not changed for this batch.

The five retained times are 15.0, 15.0, 16.0, 16.0, 16.0 ms, median **16.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/qtclustering_gpt-5.6-sol-xhigh_hybrid_r2.md), `qtclustering_gpt-5.6-sol-xhigh_hybrid_r2`, had times 169.0, 167.0, 169.0, 169.0, 168.0 ms and median 169.0 ms. The old/new median ratio is 10.5625x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/4500d708ad5c7b5d1594f93704011d6dfbca09a1/20260901-162328/qtclustering_claude-opus-5-cc-medium_hybrid_r1/qtclustering/qtclustering.cpp); file SHA-256 `c227365c7f4ae910c1317938962d9bf890f01999562ae60bf2e21801ff208a61`. Timing-fixed flag: **true**. The accepted timing-only correction and scoped revalidation remain part of the record; the original is available at commit `db27e2872a28b900024d318f6a3004a3a7fddfa7`.

## Implementation and timing

Seeds are distributed cyclically across ranks. A warp grows each candidate, carrying incremental maximum squared distances and compacting the admissible list. It saves the membership of its best seed, so the winning candidate need not be regrown. MPI_MAXLOC selects the largest cluster with the smallest seed on ties; the owner broadcasts a membership bitmask. Squared-distance near ties have an explicit square-root repair path.

GPU result copies are synchronous, and the corrected elapsed milliseconds are combined by `MPI_MAX`. All clustering rounds, host compaction, and collectives are inside the interval. GPU allocation and an empty warm-up launch are outside it. Host OpenMP helpers are adaptive: at N=5000 their 16384-element threshold serializes the timed host loops; the heavy parallel work here is MPI plus CUDA, not substantial OpenMP CPU compute.

Warp-local candidate growth and removal of repeated dense-distance accesses plausibly explain the 10.6x improvement. This interpretation is specific to the measured input and the prompt's hybrid use 'as appropriate'; it should not be presented as evidence that all three technologies contribute equal compute speedup.

## Limits and release decision

Correctness-only checks match the unchanged sequential reference at N=1200 and all
four new QT winners agree on complete result blocks and membership hashes at N=4000,
5000, 6200 and 7800. Full-size agreement is supporting evidence, not a reference proof;
the direct sequential N=4000 attempt exceeded its 240-second budget.
[Commands, output and hashes](../2026-09-29-qt-winner-correctness.json) are retained.
No probe timing enters the benchmark dataset.

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
