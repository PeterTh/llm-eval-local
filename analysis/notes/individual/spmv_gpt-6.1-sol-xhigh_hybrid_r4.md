# `spmv_gpt-6.1-sol-xhigh_hybrid_r4`

Date: 2026-10-11

## Scope

Hybrid SpMV, 18,000 rows, approximately 8.1 million nonzeros and 50,000
iterations across four ranks and four GPUs. The median is 1,666.999 ms.

## Finding

Contiguous CSR partitions balance nonzeros plus a small per-row cost. At this
size, the adaptive kernel assigns one 32-lane warp to each row, with four warps
per block. Matrix and vector data stay device-resident, and CUDA Graphs submit
batches of 64 repeated kernels to reduce launch overhead; the final 16
iterations use direct launches.

## Close-group comparison

Sol 6.1 xhigh r2 reaches 1,705.094 ms with eight-warps-per-block kernels and
64-launch graphs. The
[previous Astra leader](spmv_gpt-6-astra-medium_hybrid_r2.md)
also uses warp-per-row CSR and graph batching, with 32 launches per graph;
its median is 1,718.238 ms. The winner's 1,665.099–1,667.770 ms samples are
separated from both peers, but its 2.2% and 3.0% median advantages remain
modest. Partitioning, block size and graph details differ together, so none is
isolated as the cause.

## Correctness and timing

Native validation and static timing review passed without correction. All
50,000 independent products are launched. Device streams synchronize and
OpenMP device workers join before the per-rank interval ends; `MPI_MAX`
includes the slowest rank. Allocation, transfers, warmup and graph capture
precede the computation interval.

## Interpretation

A consistent small improvement in the established GPU-resident, graph-batched
SpMV family, not a distinct algorithmic outlier.
