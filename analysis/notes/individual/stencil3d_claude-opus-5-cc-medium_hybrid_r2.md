# `stencil3d_claude-opus-5-cc-medium_hybrid_r2`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `stencil3d/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-x 384 -i 2800`; calibration and resources were not changed for this batch.

The five retained times are 1463.0, 1464.0, 1462.0, 1461.0, 1465.0 ms, median **1463.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/stencil3d_gpt-5.2_hybrid_r4.md), `stencil3d_gpt-5.2_hybrid_r4`, had times 2984.0, 3091.0, 2856.0, 2814.0, 2873.0 ms and median 2873.0 ms. The old/new median ratio is 1.9638x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/4500d708ad5c7b5d1594f93704011d6dfbca09a1/20260901-162328/stencil3d_claude-opus-5-cc-medium_hybrid_r2/stencil3d/stencil3d.cpp); file SHA-256 `0caf412376f662c1642521997099548aac2227a25b07c28aefc700b649dea155`. Timing-fixed flag: **true**. The accepted timing-only correction and scoped revalidation remain part of the record; the original is available at commit `db27e2872a28b900024d318f6a3004a3a7fddfa7`.

## Implementation and timing

Z slabs are distributed over ranks. Separate boundary and bulk CUDA kernels prioritize halo-producing planes; node-local shared-memory windows allow direct staged GPU copies between neighbors while the interior runs. Double-buffered halo slots, events, and per-stream waits prevent reuse before consumers finish. Off-node neighbors use nonblocking MPI messages, a path not exercised by the retained single-node benchmark.

The kernel rolls through 32 Z planes in registers. A multiply plus FMA residual correction implements division by seven; this is a rounding-sensitive optimization, so retained numerical validation matters. Fixed physical boundaries are initialized in both buffers and do not need repeated copying.

The corrected timer starts before the world barrier and ends after all 2800 iterations, device synchronization, and another world barrier. It measures a common-start distributed interval, not root's kernel-launch latency. The roughly 1.96x gain is compatible with lower memory/halo overhead. No new ablation isolates division, register tiling, and shared-window exchange.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
