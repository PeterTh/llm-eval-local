# `cahn-hilliard_claude-opus-5-cc-medium_hybrid_r5`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `cahn-hilliard/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-x 512 -i 100`; calibration and resources were not changed for this batch.

The five retained times are 428.0, 437.0, 445.0, 435.0, 444.0 ms, median **437.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/cahn-hilliard_gpt-5.2_hybrid_r5.md), `cahn-hilliard_gpt-5.2_hybrid_r5`, had times 458.0, 468.0, 467.0, 468.0, 463.0 ms and median 467.0 ms. The old/new median ratio is 1.0686x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/cahn-hilliard_claude-opus-5-cc-medium_hybrid_r5/cahn-hilliard/cahn_hilliard.cpp); file SHA-256 `fc4d40c441946fb566503efdee45bea769a334c8b130c2998d8e20ba40e88b96`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

The domain is split into Z slabs. Each rank uses two concentration ghost planes, recomputing chemical potential on the inner ghost plane so each step needs one concentration halo exchange instead of separate concentration and potential exchanges. CUDA threads roll through four Z planes in registers. Boundary updates are launched first; events and separate streams let halo staging overlap the interior sweeps.

The main loop waits for both halo and bulk streams before swapping buffers. Final device synchronization and a communicator barrier precede the elapsed-time calculation, and the world `MPI_MAX` covers the reported duration. OpenMP handles host initialization and validation, not the GPU stencil itself.

This is a modest improvement with a concrete communication/overlap mechanism. Input allocation, initial halo establishment, and output assembly are not included in the kernel time. Retained validation supports the clamped-boundary implementation; static inspection is not a proof for arbitrary grid shapes or multi-node topologies.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
