# `matmul_claude-fable-5-cc-medium_cuda_r5`

Date: 2026-10-02

## Scope

CUDA matrix multiplication, N=8,192. The median is 1,719 ms, versus 1,729 ms for
Fable r1 and 1,734.944 ms for Luna 5.6 xhigh r4.

## Finding

A conventional double-precision tiled kernel uses 32×32 shared-memory tiles and
16×16 threads, each accumulating a 2×2 output patch in registers.

## Close-group comparison

The [Luna review](matmul_gpt-5.6-luna-xhigh_cuda_r4.md) already describes essentially
this tile/register arrangement. Fable r1 uses larger 64-wide tiles and 4×4 register
patches. Its 1,716–1,729 ms range overlaps the winner's 1,719 ms samples. The lead
is only 0.6% over r1 and 0.9% over the older winner.

## Correctness and timing

Retained validation passed. Every output accumulates the full inner dimension and
device synchronization completes the timed multiplication. Allocation, transfers
and a full warmup multiplication are outside the interval.

## Interpretation

A near tie in an established tiled-GEMM group. The result is not evidence of a
large algorithmic advantage specific to this model or repetition.
