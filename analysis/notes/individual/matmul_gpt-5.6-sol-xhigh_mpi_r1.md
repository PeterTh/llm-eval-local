# `matmul_gpt-5.6-sol-xhigh_mpi_r1`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the first-place outlier in the `matmul` MPI cell for data
release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark multiplied 6,144 x 6,144 matrices on 128 MPI ranks. Its
times are 405, 399, 400, 402, and 390 ms, giving a median of 400 ms. The
runner-up has a 615 ms median, so this run is 1.54x faster.

## Finding

The performance difference is already present in the local multiplication
kernel. Communication overlap prevents the winner's distributed SUMMA
algorithm from giving that kernel advantage back.

The implementation uses a two-dimensional process grid and approximately
256-wide SUMMA panels. Local rows and columns are padded to the 3 x 16 AVX2
microkernel shape. Twelve vector accumulators keep three rows by sixteen
columns in registers for a complete panel. Ordinary terms use explicit
multiply/add operations to preserve the required accumulation semantics.

Two panel-buffer sets allow the next A-row and B-column broadcasts to be
posted with `MPI_Ibcast` before the current panel is multiplied. Computation
therefore overlaps much of the following panel's communication.

The runner-up avoids timed communication entirely by independently generating
the full A row slab and B column slab needed by each rank. Its local kernel is
a conventional compiler-vectorized i-k-j traversal with 32 x 128 x 128 cache
tiles, but it lacks the explicit multi-row, multi-vector register microkernel.

## Controlled evidence

The two exact local kernels were timed independently on one physical core using
a representative 384 x 768 local output block and all 6,144 inner terms.
The winner's 24 panel calls took 0.2972-0.2974 s. The runner-up's complete
blocked kernel took 0.4713-0.4727 s. Both produced the same controlled
checksum.

The isolated ratio is 1.59x, closely matching the retained 615/400 = 1.54x
ratio. Because the runner-up has no measured communication, this experiment
shows that the explicit AVX2 microkernel is sufficient to explain first place.
The winner's double-buffered broadcasts are then effective enough to keep
distributed communication from erasing that local advantage.

## Correctness and timing validity

Every process-grid block covers disjoint output elements, and SUMMA broadcasts
all K panels needed by each block. The microkernel retains increasing K order
within each output. Padding affects only storage, and result gathering removes
the padding. The retained validation passed internal validation and external
output comparison.

Timing begins after an MPI barrier. It covers the initial panel posts, every
broadcast wait, all panel multiplications, and any communication not hidden by
computation. Rank zero reports an `MPI_MAX` reduction of per-rank elapsed
times. The independent static timing audit classified the timer as valid with
high confidence.

## Interpretation

This is a valid SIMD microkernel outlier with successful communication overlap.
It is not evidence that SUMMA communication is free; rather, its local kernel
is about 1.6x faster and the nonblocking panel pipeline preserves almost all of
that benefit at 128 ranks.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The local-kernel measurements omit MPI deliberately and are explanatory,
  not replacement benchmark data.
