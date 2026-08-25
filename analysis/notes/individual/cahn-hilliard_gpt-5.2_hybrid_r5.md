# `cahn-hilliard_gpt-5.2_hybrid_r5`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `cahn-hilliard` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 512-cubed grid
for 100 iterations on four MPI ranks and four GPUs. The five times are 458, 468, 467,
468, and 463 ms, with a 467 ms median. The next median is 476 ms.

## Finding

The program partitions the domain into GPU-resident Z slabs. Each step computes the
concentration and chemical-potential stencils on CUDA, exchanges the required halo
planes between ranks, and overlaps work on independent interior planes with staged or
CUDA-aware communication. Its CUDA kernels use direct, coalesced global-memory reads.

## Close-group comparison

The runner-up has the same distributed Z-slab decomposition, two-stencil recurrence,
halo semantics, and overlap structure. Its main difference is a shared-memory X/Y
tile inside each local stencil kernel. It reaches 476 ms, only 1.9% behind, so two
different GPU microkernels converge on nearly the same overall performance.

Additional fast results return to direct global-memory stencils with comparable halo
overlap. The common determinant is the distributed solution shape; shared-memory
tiling is neither necessary nor clearly beneficial for this case.

## Correctness and timing validity

Both fields exchange the halo state required by the next dependent sweep, and the
interior/boundary split does not omit any cells. Each rank measures the complete timed
phase, and the reported result is the slowest-rank time. Retained internal validation
and external output comparison passed.

## Interpretation

This is a valid but close first place. The result favors a simpler direct-memory GPU
kernel, while the near tie shows that the distributed decomposition and communication
overlap matter more than the local tiling choice.

## Non-decisions

- No timing correction or rerun is indicated.
- No retained data or score is changed.
