# `matmul_gpt-5.6-sol-medium_hybrid_r5`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `matmul` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark multiplied 8,192 x
8,192 matrices on four MPI ranks and four GPUs. Its five times are 457.351, 463.047,
461.878, 457.076, and 463.916 ms, with a 461.878 ms median. The next median is
463.320 ms, followed by several results below 472 ms.

## Finding

The program gives each rank a contiguous row range of A and C while replicating B on
all four GPUs. Its local CUDA kernel uses a 32 x 32 shared-memory tile, 32 x 8 threads,
and four output rows per thread. Because B is immutable and already replicated, the
timed multiplication needs no inter-rank communication.

## Close-group comparison

The two nearest implementations use essentially the same row distribution, replicated
B, and 32 x 32 / four-rows-per-thread kernel. Their sub-percent median differences are
ordinary variation. Slightly farther members use a 16 x 16 one-output-per-thread GPU
kernel while keeping the same MPI layout and still finish within about 2%.

The immediate group therefore shares the same overall solution and local kernel shape;
the broader close group reaches similar performance with a different GPU tile but not
a different distributed algorithm.

## Correctness and timing validity

Each rank computes all columns for its complete C row range, and gathering occurs only
after the timed multiplication. Rank-local elapsed values are reduced with `MPI_MAX`
after CUDA completion. Retained internal validation and external output comparison
passed.

## Interpretation

This is a practical tie at the top. Replicating B and partitioning output rows is the
important successful design; the precise first-place median is not a distinct model-
generated optimization.

## Non-decisions

- No source, measurement, threshold, or score is changed.
- The close group is described, not collapsed in the retained data.
