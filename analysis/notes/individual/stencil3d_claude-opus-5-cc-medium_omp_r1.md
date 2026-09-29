# `stencil3d_claude-opus-5-cc-medium_omp_r1`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `stencil3d/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-x 512 -i 20`; calibration and resources were not changed for this batch.

The five retained times are 346.0, 351.0, 351.0, 347.0, 347.0 ms, median **347.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/stencil3d_gpt-5.6-sol-xhigh_omp_r5.md), `stencil3d_gpt-5.6-sol-xhigh_omp_r5`, had times 466.0, 466.0, 466.0, 464.0, 466.0 ms and median 466.0 ms. The old/new median ratio is 1.3429x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/stencil3d_claude-opus-5-cc-medium_omp_r1/stencil3d/stencil3d.cpp); file SHA-256 `0e3c0439f3a1c6544336cb4d353ab054387ee998b780acdb53856c4759eaf76e`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

A persistent OpenMP team covers all 20 iterations. Threads partition the Y/Z interior into balanced regions, with cache-sized Y blocking so neighboring Z planes are reused. For fields larger than the observed aggregate cache, output uses non-temporal stores with a completion fence. Static first touch and work assignment aim to keep the large arrays NUMA-local.

The interior seven-point update and fixed-boundary behavior remain present; buffers alternate by iteration parity. The stop timestamp follows the full parallel region, so all worker stores and iteration barriers precede timing completion. Initialization and cache/topology discovery are outside the stencil timer.

The 1.34x gain is consistent with reduced memory traffic in a bandwidth-bound kernel. The optional affinity helper defers to the campaign's explicit binding; it is not evidence of extra resources. Retained validation supplies the numerical check, while no streaming-store or blocking ablation quantifies the contribution of each optimization.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
