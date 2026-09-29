# `black-scholes_claude-opus-5-cc-medium_omp_r4`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `black-scholes/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 25000000`; calibration and resources were not changed for this batch.

The five retained times are 22.551, 21.196, 21.131, 22.058, 22.551 ms, median **22.058 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/black-scholes_gpt-5.6-terra-medium_omp_r1.md), `black-scholes_gpt-5.6-terra-medium_omp_r1`, had times 24.123, 23.796, 23.462, 23.325, 23.529 ms and median 23.529 ms. The old/new median ratio is 1.0667x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/black-scholes_claude-opus-5-cc-medium_omp_r4/black-scholes/black_scholes.cpp); file SHA-256 `1a67de32f288f3ae646995c31f76c9688fac9c8d8f3d47148d07d063624a76e4`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

The timed loop calls the complete `blackScholes` formula for every option, including logarithm, square root, exponentials, and normal CDF evaluations. It does not use the hybrid winner's memoization. Static row-range scheduling matches parallel first-touch initialization of both the option and result buffers, helping NUMA locality. The affinity helper defers to explicitly configured OpenMP placement, as used by this campaign; its presence alone does not explain the win.

The OpenMP loop's implicit completion precedes the stop timestamp. Initialization and validation remain outside the measured pricing kernel. A 6.7% median improvement is compatible with better placement and loop organization, but the retained data does not isolate their causal contributions. This is a modest kernel improvement, not evidence of a different pricing algorithm.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
