# `qtclustering_claude-opus-5-cc-medium_mpi_r5`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `qtclustering/mpi` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 4000`; calibration and resources were not changed for this batch.

The five retained times are 12.0, 10.0, 12.0, 13.0, 12.0 ms, median **12.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/qtclustering_gpt-5.6-sol-xhigh_mpi_r2.md), `qtclustering_gpt-5.6-sol-xhigh_mpi_r2`, had times 31.0, 29.0, 30.0, 29.0, 31.0 ms and median 30.0 ms. The old/new median ratio is 2.5000x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/4500d708ad5c7b5d1594f93704011d6dfbca09a1/20260901-162328/qtclustering_claude-opus-5-cc-medium_mpi_r5/qtclustering/qtclustering.cpp); file SHA-256 `df89c8c4d84de22bdff4cb44a51d1c517bfa11d70c2eebc30f1b78710d7610a4`. Timing-fixed flag: **true**. The accepted timing-only correction and scoped revalidation remain part of the record; the original is available at commit `db27e2872a28b900024d318f6a3004a3a7fddfa7`.

## Implementation and timing

The largest optimization is candidate-cluster memoization. A seed's cached greedy cluster remains valid while none of its chosen members has been removed: deleting unchosen alternatives cannot change any of the previous greedy choices. Only invalidated seeds are regrown. Each regrowth maintains candidate maximum distances incrementally and permanently removes infeasible candidates. Cyclic ownership spreads the spatially correlated seed work across ranks.

MPI_MAXLOC selects the largest cluster with lowest-seed tie-breaking; its owner broadcasts the member list. The corrected timer encloses setup inside `qtClustering`, all rounds, and a trailing barrier, then explicitly reduces the elapsed milliseconds with `MPI_MAX`.

The 2.5x gain is consistent with doing much less redundant candidate construction. At 12 ms, however, integer quantization and synchronization overhead make the exact ratio coarse. This is not an end-to-end or multi-node scalability claim, and there was no cache-disabled performance ablation.

## Limits and release decision

Correctness-only checks match the unchanged sequential reference at N=1200 and all
four new QT winners agree on complete result blocks and membership hashes at N=4000,
5000, 6200 and 7800. Full-size agreement is supporting evidence, not a reference proof;
the direct sequential N=4000 attempt exceeded its 240-second budget.
[Commands, output and hashes](../2026-09-29-qt-winner-correctness.json) are retained.
No probe timing enters the benchmark dataset.

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
