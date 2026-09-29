# `matmul_claude-opus-5-cc-medium_hybrid_r2`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `matmul/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 8192`; calibration and resources were not changed for this batch.

The five retained times are 261.0, 265.0, 261.0, 258.0, 261.0 ms, median **261.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/matmul_gpt-5.6-sol-medium_hybrid_r5.md), `matmul_gpt-5.6-sol-medium_hybrid_r5`, had times 457.351, 463.047, 461.878, 457.076, 463.916 ms and median 461.878 ms. The old/new median ratio is 1.7696x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/4500d708ad5c7b5d1594f93704011d6dfbca09a1/20260901-162328/matmul_claude-opus-5-cc-medium_hybrid_r2/matmul/matmul.cpp); file SHA-256 `3beb464609b5dcaf4cb87e9a840386aa4fc143ba60c07f6adfb80b367982a734`. Timing-fixed flag: **true**. The accepted timing-only correction and scoped revalidation remain part of the record; the original is available at commit `db27e2872a28b900024d318f6a3004a3a7fddfa7`.

## Implementation and timing

MPI partitions output rows. Within each rank, an auto-tuned split assigns rows to a tiled double-precision CUDA kernel and a packed AVX2/FMA OpenMP kernel concurrently. Node-local result storage is shared; only node leaders gather across nodes. Short tuning trials are outside the measured multiply, and the final multiply recomputes all assigned output rows.

The corrected timer begins before a world barrier, then encloses GPU launches, CPU computation, result downloads, device synchronization, a node barrier, and any node-leader gather. On the measured single node, root's interval brackets the common-start work and completion of all local ranks; this is the accepted synchronized-interval alternative to explicitly reducing local durations.

The 1.77x gain is consistent with genuinely using CPU and GPU throughput together, plus packed CPU microkernels. It does not include the cost of autotuning or initial matrix generation. No tuning/CPU-off/GPU-off ablation was performed, so their separate contributions are not quantified. The retained corrected measurement is used unchanged.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
