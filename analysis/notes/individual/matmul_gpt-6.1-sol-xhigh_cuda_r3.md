# `matmul_gpt-6.1-sol-xhigh_cuda_r3`

Date: 2026-10-11

## Scope

CUDA matrix multiplication, 8,192² double-precision matrices on one GPU. The
median is 1,716 ms, compared with 1,719 ms for the previous best.

## Finding

The custom GEMM kernel uses 64×64 output tiles, a K depth of 16 and 256-thread
blocks. Each thread accumulates an 8×2 register patch; shared-memory staging
reuses input tiles, with padding on A and a full-tile path that avoids edge
checks. The complete double-precision dot products are computed with fused
multiply-adds.

## Close-group comparison

The [previous Fable leader](matmul_claude-fable-5-cc-medium_cuda_r5.md)
uses smaller shared tiles and 2×2 per-thread register patches. Its five 1,719 ms
samples sit inside this winner's 1,716–1,738 ms range; Sol 6.1 xhigh r4 is also
close at 1,723.390 ms. The 0.17% median lead does not establish that the larger
register tile is faster. Unlike Fable, this source does not perform an extra
full GEMM before starting its internal timer.

## Correctness and timing

Native validation passed without a timing correction. Device initialization
finishes before the timer; the entire multiplication and its device
synchronization are timed. Result copying and validation follow it. There is no
library substitution or reduced-precision arithmetic shortcut.

## Interpretation

A practical tie within the tiled double-precision GEMM group.
