# `cholesky_claude-opus-5-cc-medium_cuda_r1`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `cholesky/cuda` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 1280`; calibration and resources were not changed for this batch.

The five retained times are 6.0, 6.0, 6.0, 6.0, 6.0 ms, median **6.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/cholesky_gpt-5.6-terra-xhigh_cuda_r4.md), `cholesky_gpt-5.6-terra-xhigh_cuda_r4`, had times 7.0, 7.0, 7.0, 7.0, 7.0 ms and median 7.0 ms. The old/new median ratio is 1.1667x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/cholesky_claude-opus-5-cc-medium_cuda_r1/cholesky/cholesky.cpp); file SHA-256 `a7e76828951b086bc31301cd3603bd619b80b8f4d770ceb59f856e74510bbd5b`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

The factorization is a 32-column right-looking blocked Cholesky: a warp factors the diagonal panel, a triangular solve handles the block column, and tiled symmetric rank updates process the trailing matrix. Finished rows are copied back on a second stream while factorization continues. This reduces launch/synchronization overhead on the narrow critical path and overlaps output transfer.

The timer wraps `choleskyDecomposition`, including its allocations, host-to-device upload, panel kernels, and row downloads. Both compute and copy streams are synchronized before return. Matrix generation and CUDA context initialization are outside the factorization timer.

The new median is just 6 ms versus 7 ms. Both results are very short and reported in whole milliseconds, so the apparent 16.7% ratio magnifies a one-tick change. The blocked implementation is credible, but the data does not support a precise 16.7% engineering improvement or extrapolation to larger matrices.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
