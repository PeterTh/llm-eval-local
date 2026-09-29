# `floydwarshall_claude-opus-5-cc-medium_omp_r4`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `floydwarshall/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 8704`; calibration and resources were not changed for this batch.

The five retained times are 1009.0, 1025.0, 1017.0, 1030.0, 1024.0 ms, median **1024.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/floydwarshall_gpt-5.6-sol-medium_omp_r2.md), `floydwarshall_gpt-5.6-sol-medium_omp_r2`, had times 1278.0, 1271.0, 1302.0, 1271.0, 1274.0 ms and median 1274.0 ms. The old/new median ratio is 1.2441x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/floydwarshall_claude-opus-5-cc-medium_omp_r4/floydwarshall/floydwarshall.cpp); file SHA-256 `947fd39c53bab763414f87aa151b8294a4aa940e9dd3c64c4169f28af4ad5965`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

The implementation uses 64-by-64 cache tiles and the standard diagonal, panel, and independent-tile phases. Panel tiles are copied to contiguous scratch space, avoiding cache-set conflicts from the full matrix's row stride. The phase-three kernel retains 32-distance chunks across the inner K block and uses branch-free SIMD comparisons and blends.

All pivot blocks are processed. The OpenMP phase boundaries enforce dependencies before independent updates proceed, and the enclosing factorization call completes before the stop timestamp. Random graph generation is kept semantically consistent with the sequential generator rather than replaced with a different graph.

A 1.24x improvement is consistent with cache and register reuse. This is a static mechanism explanation supported by retained output comparison, not an isolated measurement of the packing benefit. General graph/path semantics beyond the existing validation cases are not newly certified by this analysis.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
