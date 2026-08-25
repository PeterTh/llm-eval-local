# `matmul_gpt-5.6-luna-xhigh_cuda_r4`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place CUDA result in the `matmul` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark multiplied 8,192 x
8,192 double-precision matrices. Its five times are 1740.526, 1732.587, 1726.252,
1746.171, and 1734.944 ms. The next medians are 1736.467 and 1737.614 ms.

## Finding

The winner is a conventional custom shared-memory GEMM, not a library call. A 16 x 16
thread block produces a 32 x 32 output tile, with each thread accumulating a 2 x 2
register block while K tiles are staged through shared memory.

## Close-group comparison

The immediate group contains both the same 32 x 32 / 2 x 2 organization and different
tilings: 64 x 64 tiles with 4 x 4 register blocks, and simpler 16 x 16 one-output-per-
thread kernels. Despite those microarchitectural differences, their medians are within
about 1% and their five-run ranges overlap strongly.

These are different kernel tilings of the same cubic blocked-multiplication algorithm.
At this large size they converge on the GPU's double-precision throughput and memory-
movement balance; no specific tile choice is shown to be uniquely superior.

## Correctness and timing validity

Every output tile covers the full K dimension. CUDA event timing surrounds all kernel
work and synchronizes before reporting; allocation and transfers are outside the
computation interval. Retained internal validation and external output comparison
passed.

## Interpretation

This is a valid statistical first place in a broad group of equally effective custom
GEMM tilings. The meaningful result is convergence on tiled GEMM, not the 1.5 ms gap
between the first two medians.

## Non-decisions

- No benchmark or scoring data is changed.
- No post-hoc tile tuning is substituted for the generated program.
