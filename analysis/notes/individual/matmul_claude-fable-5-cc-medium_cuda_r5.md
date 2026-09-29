# `matmul_claude-fable-5-cc-medium_cuda_r5`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `matmul/cuda` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 8192`; calibration and resources were not changed for this batch.

The five retained times are 1719.0, 1719.0, 1719.0, 1719.0, 1719.0 ms, median **1719.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/matmul_gpt-5.6-luna-xhigh_cuda_r4.md), `matmul_gpt-5.6-luna-xhigh_cuda_r4`, had times 1740.526, 1732.587, 1726.252, 1746.171, 1734.944 ms and median 1734.944 ms. The old/new median ratio is 1.0093x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/matmul_claude-fable-5-cc-medium_cuda_r5/matmul/matmul.cpp); file SHA-256 `62ad882ab0c72bfce1ae02bb4249eeaa970b6956f859b78a2405eed1634e7bea`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

Fable produces a conventional double-precision tiled GEMM: 32-by-32 output tiles, 16-by-16 threads, and a 2-by-2 register accumulator per thread. Cooperative loads stage both operands in shared memory; boundary checks zero-pad partial tiles. The complete K dimension is accumulated, with no input-specific shortcut.

`matrixMultiply` launches the kernel and calls `cudaDeviceSynchronize`. The host timer surrounds that call. Allocation, input uploads, a complete untimed warm-up multiply, and the final result download are outside the reported kernel interval.

All five new values are 1719 ms because output is truncated to whole milliseconds. The previous winner's spread is 1726.252–1746.171 ms; the median lead is only 0.93%. Treat this as a near tie, not a demonstrated advantage of Fable's model size or a large new kernel optimization. The comparison is kernel time, not end-to-end execution time.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
