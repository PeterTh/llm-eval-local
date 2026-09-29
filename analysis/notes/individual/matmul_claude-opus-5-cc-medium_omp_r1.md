# `matmul_claude-opus-5-cc-medium_omp_r1`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `matmul/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 8832`; calibration and resources were not changed for this batch.

The five retained times are 473.0, 484.0, 474.0, 473.0, 470.0 ms, median **473.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/matmul_gpt-5.6-sol-xhigh_omp_r3.md), `matmul_gpt-5.6-sol-xhigh_omp_r3`, had times 1169.0, 1151.0, 1144.0, 1135.0, 1143.0 ms and median 1144.0 ms. The old/new median ratio is 2.4186x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/matmul_claude-opus-5-cc-medium_omp_r1/matmul/matmul.cpp); file SHA-256 `50ce573e908111bce0765cfce5a7458f197441e6b8d98073a172176264b14587`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

A two-dimensional thread grid assigns disjoint output microtiles. Cache-blocked packing feeds a 6-by-8 AVX2/FMA microkernel; each thread has cache-line-separated scratch storage, allocated once for the team. Packing B is conditional on expected reuse. The complete K dimension is processed in order, and partial edge tiles have a separate padded path.

The measured `matrixMultiply` includes workspace allocation, operand packing, all block updates, and the final OpenMP join. Input generation and first touch occur beforehand. Explicit campaign affinity is respected by the optional binding helper, so there is no claim that the helper changed the campaign's resource allocation.

The 2.42x median gain is consistent with high arithmetic intensity and register reuse rather than skipped matrix work. Retained validation passed. The source is an implementation-level explanation; without a packing or microkernel ablation, their individual shares of the gain remain hypotheses.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
