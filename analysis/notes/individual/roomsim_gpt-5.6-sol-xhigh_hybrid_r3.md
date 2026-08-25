# `roomsim_gpt-5.6-sol-xhigh_hybrid_r3`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `roomsim` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used 5,120 triangles
and 2,000 time steps on four MPI ranks and four GPUs. Its five total times are 341,
342, 342, 342, and 344 ms, giving a 342 ms median. The runner-up median is 356 ms.

## Finding

The implementation partitions contiguous receiver rows among ranks. Each rank stores
its local dense form-factor and delay rows on one GPU, while the complete radiosity
history is replicated. Every propagation step computes local receivers on the GPU
and uses `MPI_Allgatherv` to make the resulting row segment available to all ranks.
Distances are correlated locally on the GPU and gathered at the end.

For form-factor sampling, a half warp cooperates on each triangle pair so the 16 ray
samples are evaluated in parallel. The propagation and lag-search kernels likewise
use block-level parallel reductions. Pinned staging buffers support systems without
direct device-buffer MPI.

## Close-group comparison

The 356 ms runner-up has the same distributed solution shape: receiver-row
partitioning, local dense matrices, replicated radiosity history, one GPU per rank,
one collective per step, and GPU-parallel correlation. Its main visible distinction
is one CUDA thread per triangle pair looping over all 16 form-factor rays, rather
than half-warp cooperation. It also has different staging and reduction details.

The winner's median is 3.9% lower. The retained phase breakdowns are close: the
winner is roughly 3 ms in precomputation, 327 ms in simulation, and 11 ms in distance;
the runner is roughly 1, 335, and 20 ms. This is a close group with the same overall
algorithm, although the winner's finer-grained ray and lag parallelism plausibly
accounts for its small advantage.

## Correctness and timing validity

All receiver rows and time steps are computed, and each all-gather completes the
replicated state needed by later steps. Reported phase times use the maximum across
ranks, so a faster local rank cannot stand in for the distributed runtime. Retained
internal validation and external output comparison passed.

## Interpretation

The result is a modest implementation-level lead inside a common distributed design,
not a fundamentally different hybrid algorithm. The 342 versus 356 ms ordering is
credible but should not be overinterpreted.

## Non-decisions

- No generated source or benchmark result is changed.
- No alternative timing result replaces the retained score.
