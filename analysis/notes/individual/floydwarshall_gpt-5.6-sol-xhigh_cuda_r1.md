# `floydwarshall_gpt-5.6-sol-xhigh_cuda_r1`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the isolated winner in the `floydwarshall` CUDA cell for
data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used an 8,192-node graph on one RTX 3090. Its times are
203, 202, 201, 200, and 203 ms, giving a median of 202 ms. The next result has
a 323 ms median, making this run 1.60x faster.

## Finding

The implementation removes the unobservable path matrix and combines that
dead-state elimination with an efficient 32 x 32 blocked CUDA kernel.

Only the final distance matrix is printed, validated, and externally compared.
The original program's path/predecessor matrix never affects an observable
result. This implementation therefore stores and updates only distances. At
8,192 nodes, omitting path removes a second 256 MiB device matrix and all
conditional path writes in the three Floyd-Warshall phases.

The dominant phase-three kernel uses a 32 x 8 CUDA block. Each thread keeps
four output distances in registers while two input tiles are loaded once into
shared memory. The matrix is column-major with the row coordinate mapped to
the contiguous thread dimension, making global transactions coalesced.

The runner-up also uses 32 x 32 tiles and four outputs per thread, but carries
four path values and four changed flags through the hot loop and conditionally
writes the path matrix. Its phase-one and phase-two kernels likewise update
path whenever a shorter route is found.

## Comparative evidence

Inspection of the next group of 323-456 ms implementations found that they all
retain a full path matrix. A slower no-path implementation exists, showing
that dead-state elimination is necessary but not sufficient; the winner also
has the stronger tiled kernel and coalesced layout.

Compilation for the recorded GPU architecture reports no spills in either
dominant kernel. The winner's large-graph phase-three kernel uses 56 registers
and 8,192 bytes of shared memory; the runner-up uses 47 registers and
8,448 bytes. This rules out an accidental spill difference and points instead
to eliminated path traffic/control plus kernel organization.

A live GPU variant could not be timed in this side-session sandbox because the
driver was unavailable. The conclusion therefore combines the retained
1.60x measurements, the cell-wide path-state census, and static CUDA compiler
evidence rather than claiming a newly measured path-only ablation.

## Correctness and timing validity

Floyd-Warshall distance updates do not depend on predecessor output. Removing
dead path stores leaves every min-plus distance operation intact. The retained
validation passed internal validation and external comparison with the
reference distance hash.

The timer begins after the input matrix is on the device. The clustering
routine ends with `cudaDeviceSynchronize`, so host timing includes every
Floyd-Warshall kernel and cannot stop early. The runner-up's CUDA-event metric
also measures kernels rather than transfers, making the cell comparison
consistent at the computation-kernel level.

## Interpretation

This is a valid dead-state and GPU-kernel outlier. The score rewards computing
the benchmark's observable distance result without maintaining a large
predecessor structure that no output consumer can see.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- Static compiler evidence is explanatory and does not replace a device
  benchmark.
