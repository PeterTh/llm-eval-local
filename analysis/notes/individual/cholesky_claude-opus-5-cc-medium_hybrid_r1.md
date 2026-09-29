# `cholesky_claude-opus-5-cc-medium_hybrid_r1`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `cholesky/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 4096`; calibration and resources were not changed for this batch.

The five retained times are 68.0, 68.0, 68.0, 68.0, 68.0 ms, median **68.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/cholesky_gpt-5.6-sol-xhigh_hybrid_r2.md), `cholesky_gpt-5.6-sol-xhigh_hybrid_r2`, had times 90.0, 92.0, 94.0, 95.0, 95.0 ms and median 94.0 ms. The old/new median ratio is 1.3824x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/cholesky_claude-opus-5-cc-medium_hybrid_r1/cholesky/cholesky.cpp); file SHA-256 `ecb16e6d12e810b4976af65187339701e85d224cd6cf65e4d973cf5378bc9f72`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

Block columns are distributed cyclically across ranks and remain resident on their GPUs. cuSOLVER factors diagonal panels and cuBLAS performs triangular solves and trailing DGEMMs. One-step lookahead prioritizes the next panel; triple-buffered panels and CUDA events protect cross-stream dependencies. Within the measured single node, shared-memory panel exchange avoids redundant MPI message copies; a node-leader ring is available for other topologies.

All panel and update work is issued within `choleskyDecomposition`. Both GPU streams are synchronized before it returns, and a world barrier completes before the stop timestamp. Thus the root's interval includes every rank's factorization work. Library warm-up and input generation are outside the interval, as is output assembly.

The 1.38x improvement is consistent with panel lookahead and efficient library kernels. OpenMP is used for host-side assembly/validation. The data is a four-GPU, single-node result; it does not test the inter-node ring's claimed scalability. No isolated panel-pipeline ablation was performed.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
