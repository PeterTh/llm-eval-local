# `nbody_claude-opus-5-cc-medium_mpi_r1`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `nbody/mpi` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 40000 -s 100`; calibration and resources were not changed for this batch.

The five retained times are 2538.0, 2534.0, 2530.0, 2531.0, 2545.0 ms, median **2534.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/nbody_gpt-5.6-sol-xhigh_mpi_r1.md), `nbody_gpt-5.6-sol-xhigh_mpi_r1`, had times 2753.0, 2734.0, 2741.0, 2747.0, 2762.0 ms and median 2747.0 ms. The old/new median ratio is 1.0841x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/nbody_claude-opus-5-cc-medium_mpi_r1/nbody/nbody.cpp); file SHA-256 `2289687b4ffe6db8d3ad900b79f460d771a8c0a673a9c1138401769cd99cadd7`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

Ranks own contiguous body ranges and replicate positions with `MPI_Allgatherv` after each step. The local force loop works on several target bodies together, exposing vectorization across targets while retaining ascending source-body order. Velocities remain local until optional output assembly. All requested all-pairs interactions and 100 steps are present.

The timer includes force evaluation, integration, and every step's position communication. An `MPI_MAX` reduction determines the reported milliseconds. Final velocity gathering is outside the simulation interval.

The 8.4% median improvement is compatible with vectorization and layout improvements in an otherwise familiar algorithm. Explicit FMA and separately rounded velocity increments attend to numerical behavior; empirical correctness is the retained validation result. No controlled local-force comparison was run, so the gain is not attributed quantitatively to SIMD alone.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
