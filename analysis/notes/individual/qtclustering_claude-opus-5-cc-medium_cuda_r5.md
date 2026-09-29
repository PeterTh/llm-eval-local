# `qtclustering_claude-opus-5-cc-medium_cuda_r5`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `qtclustering/cuda` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 7800`; calibration and resources were not changed for this batch.

The five retained times are 41.0, 43.0, 43.0, 43.0, 43.0 ms, median **43.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/qtclustering_gpt-5.6-sol-xhigh_cuda_r2.md), `qtclustering_gpt-5.6-sol-xhigh_cuda_r2`, had times 800.0, 804.0, 799.0, 810.0, 808.0 ms and median 804.0 ms. The old/new median ratio is 18.6977x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/qtclustering_claude-opus-5-cc-medium_cuda_r5/qtclustering/qtclustering.cpp); file SHA-256 `367bae56cc63b9398ad31571c6c7e1f14aafd23a9d7609d2a7e452e5fd74fb41`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

The whole greedy outer loop lives in one cooperative kernel, avoiding a launch and host round trip for every committed cluster. One warp grows each seed's candidate, compacting infeasible points and maintaining maximum distances incrementally. Up to 128 candidates per warp stay in shared memory, with a global spill path. Active points are compacted in order, preserving seed/index tie-breaking.

Single precision screens candidate distances using a conservative error window for the generator's bounded coordinates. Isolated candidates safely inside the threshold are selected directly; ambiguous candidates are re-evaluated against actual members in double precision. This is a filtered mixed-precision algorithm, not wholesale conversion of the clustering decisions to float. General bitwise equivalence at every floating-point tie is not established merely by its comments.

The timer wraps allocation, upload, initialization, the cooperative kernel, synchronous result downloads, host reconstruction, and cleanup. Only CUDA context setup precedes it. The 18.7x gain has strong structural explanations—warp-level growth, pruning, mixed-precision screening, and removal of per-cluster launches—but no ablation assigns a separate factor to each.

## Limits and release decision

Additional correctness-only checks found identical complete result blocks, including
the membership hash, against the unchanged sequential reference at N=1200. All four
new QT winners also agree at N=4000, 5000, 6200 and 7800. This supports the measured
paths without claiming a full-size reference proof: the direct sequential N=4000
attempt timed out after 240 seconds. [Commands, output and hashes](../2026-09-29-qt-winner-correctness.json)
are retained; these probe timings never enter the benchmark dataset.

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
