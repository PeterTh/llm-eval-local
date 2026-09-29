# `nbody_claude-opus-5-cc-medium_hybrid_r3`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `nbody/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 50000 -s 30`; calibration and resources were not changed for this batch.

The five retained times are 907.0, 788.0, 1098.0, 853.0, 786.0 ms, median **853.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/nbody_gpt-5.6-terra-xhigh_hybrid_r3.md), `nbody_gpt-5.6-terra-xhigh_hybrid_r3`, had times 1744.604, 1740.221, 1739.388, 1737.937, 1742.917 ms and median 1740.221 ms. The old/new median ratio is 2.0401x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/nbody_claude-opus-5-cc-medium_hybrid_r3/nbody/nbody.cpp); file SHA-256 `93b3e1c21ba7397b4553b0e851bac4bbb470bfe13e9901739ae954815c452faa`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

MPI assigns body slices and republishes positions each step. GPU kernels evaluate all pair interactions for their slices using shared-memory tiles and segmented partial sums; a second kernel combines segments and integrates positions. OpenMP computes another slice concurrently. The CPU/GPU split is adjusted from observed worker throughput after each step.

The timed loop includes host/device transfers, CPU work, GPU stream completion, the adaptive split, and all three position all-gathers on every step. `MPI_MAX` aggregates elapsed time. The final velocity replication is output preparation outside the interval, not work needed for subsequent simulated steps.

Combining host and accelerator work plausibly explains the roughly twofold gain. Segmented GPU sums and CPU reduction order can differ from the sequential accumulation; retained tolerance-based validation passed, but this is not a claim of bitwise equivalence for arbitrary long chaotic trajectories. The benchmark keeps its original 30 steps; no convergence shortcut is present.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
