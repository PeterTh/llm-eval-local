# `nbody_claude-opus-5-cc-medium_omp_r4`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `nbody/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 20000 -s 100`; calibration and resources were not changed for this batch.

The five retained times are 645.0, 639.0, 641.0, 639.0, 640.0 ms, median **640.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/nbody_gpt-5.6-sol-xhigh_omp_r3.md), `nbody_gpt-5.6-sol-xhigh_omp_r3`, had times 638.0, 641.0, 646.0, 639.0, 642.0 ms and median 641.0 ms. The old/new median ratio is 1.0016x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/nbody_claude-opus-5-cc-medium_omp_r4/nbody/nbody.cpp); file SHA-256 `e0da92f4eb16098510c3cece7b8906db3ce08d79e545741b2d7d5e0012e8fccd`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

Structure-of-arrays positions feed an eight-target force tile. SIMD operates across target bodies, keeping each body's source-body traversal in ascending order. A single OpenMP team spans all time steps; a barrier completes force updates before integration and the next step. Explicit FMA expressions make the intended rounding sequence visible.

The outer host timer wraps the full 100-step `runSimulation`, including team creation and completion. Diagnostics and output serialization are outside the interval. No work is left asynchronous at the stop timestamp.

The old and new five-sample ranges overlap: a 641-to-640 ms change is only 0.16%. This is a practical tie. The result supports another competent vectorized all-pairs implementation, not a measurable new performance frontier. The nominal winner follows the unchanged median-ranking rule; this review does not adjust scores to manufacture a statistically significant separation.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
