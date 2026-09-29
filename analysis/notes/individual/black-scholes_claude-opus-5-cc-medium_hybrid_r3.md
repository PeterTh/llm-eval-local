# `black-scholes_claude-opus-5-cc-medium_hybrid_r3`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `black-scholes/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 100000000`; calibration and resources were not changed for this batch.

The five retained times are 12.087, 11.892, 11.418, 11.855, 11.772 ms, median **11.855 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/black-scholes_claude-opus-4.6_hybrid_r5.md), `black-scholes_claude-opus-4.6_hybrid_r5`, had times 21.653, 21.68, 21.655, 21.661, 21.646 ms and median 21.655 ms. The old/new median ratio is 1.8267x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/black-scholes_claude-opus-5-cc-medium_hybrid_r3/black-scholes/black_scholes.cpp); file SHA-256 `2d22ebdaaa703dd6b5e2bbc8e043b6d84273724236a29b8186af08501b4170f7`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

`priceOption` exploits the generated input family: all options are scaled copies of seven base cases. A 7-by-9 table memoizes transcendental values for nearby representable spot/strike ratios. Lookup requires exact ratio equality and otherwise falls back to the full formula; the final scaled prices are still evaluated per option. This is substantially less work than the previous winner's full transcendental-heavy GPU kernel, not merely a faster MPI reduction.

MPI distributes contiguous option ranges. OpenMP CPU workers and CUDA-stream feeder threads claim disjoint tiles from atomic counters; GPU results are copied back and each stream is synchronized before its worker finishes. The timer encloses the parallel pricing region and reduces microseconds with `MPI_MAX`.

The small memoization table, device setup, and warm-up are outside the timer. This is an input-family-specialized kernel result, not general-purpose or end-to-end option-pricing throughput. The constant-size table work is a timing-scope caveat; no new rank-local undermeasurement was found. No ablation measures the individual contributions of memoization and load balancing.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
