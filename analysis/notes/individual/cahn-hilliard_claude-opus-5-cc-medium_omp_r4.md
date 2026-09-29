# `cahn-hilliard_claude-opus-5-cc-medium_omp_r4`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `cahn-hilliard/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-x 512 -i 30`; calibration and resources were not changed for this batch.

The five retained times are 490.0, 487.0, 493.0, 489.0, 484.0 ms, median **489.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/cahn-hilliard_gpt-5.6-sol-medium_omp_r2.md), `cahn-hilliard_gpt-5.6-sol-medium_omp_r2`, had times 2259.0, 2267.0, 2265.0, 2258.0, 2266.0 ms and median 2265.0 ms. The old/new median ratio is 4.6319x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/cahn-hilliard_claude-opus-5-cc-medium_omp_r4/cahn-hilliard/cahn_hilliard.cpp); file SHA-256 `a698f845b1801b95e2686b4529f43216c150b37df6586f0f37baea9f6a5fb6ba`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

The important change relative to the previous winner's two full-grid sweeps is `fusedStep`: chemical potential is produced into a per-thread three-plane ring buffer and consumed immediately by the concentration update. Tiles recompute a narrow potential halo, exchanging a small amount of arithmetic for avoiding full-grid intermediate-field traffic. The large 512-cubed case selects this cache-blocked path; the ordinary two-sweep path remains for cache-resident cases.

X remains contiguous, tile ownership is stable, and large output rows use streaming stores. A store fence and OpenMP barriers complete each update before the shared buffer swap. One parallel region encloses all 30 iterations, and the outer wall-clock timer ends after the team finishes.

The 4.6x gain is consistent with a major memory-traffic reduction rather than omitted iterations. The retained correctness test passed, and the inspected fused loop covers the same two stencil operations and boundary handling. No controlled ablation was performed here, so the exact fraction due to fusion versus locality and stores remains unmeasured.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
