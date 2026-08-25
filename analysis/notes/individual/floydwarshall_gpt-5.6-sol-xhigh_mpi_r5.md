# `floydwarshall_gpt-5.6-sol-xhigh_mpi_r5`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the first-place outlier in the `floydwarshall` MPI cell
for data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used an 8,192-node graph on 128 MPI ranks. Its times
are 796, 785, 805, 785, and 784 ms, giving a median of 785 ms. The runner-up
has a 1,101 ms median, making this run 1.40x faster.

## Finding

The dominant difference is a simpler phase-three local update loop. The winner
uses a row-k-column traversal and unconditional `min` assignment across the
complete local column range. The runner-up subdivides each local row into
256-column ranges and uses a compare followed by a conditional store.

Both versions use 64-wide blocked Floyd-Warshall, a two-dimensional process
grid, concurrent nonblocking broadcasts of the phase-three row and column
panels, and no unobservable path matrix. Their communication volume and
asymptotic local work are therefore similar.

On the evaluated process grid, a representative local block is 512 x 1,024.
The 64 pivot rows occupy 256 KiB and a local output row occupies 4 KiB, so the
complete panel is already compatible with the CPU's 512 KiB private L2. The
extra 256-column subdivision does not create needed locality. It instead
breaks the hot range into repeated short calls and revisits the pivot-row set
for every subrange.

The winner also starts the two diagonal-tile broadcasts concurrently. The
runner-up performs a blocking broadcast and its pivot-row update before
entering the second blocking broadcast on the pivot column. That serializes
part of the phase-two critical path, but the controlled evidence shows that
the local phase-three loop is sufficient to explain the gap.

## Controlled evidence

The exact runner-up phase-three update was benchmarked independently for 64
repetitions on a 512 x 1,024 local block with a 64-wide pivot:

| Variant | Kernel time |
|---|---:|
| Original 256-column subdivision and conditional update | 0.341-0.377 s |
| Change only the conditional update to unconditional `min` | 0.293-0.307 s |
| Also remove the unnecessary 256-column subdivision | 0.204-0.208 s |

All variants produced the same checksum. Compiler diagnostics show that the
original loop is vectorized, but its conditional update becomes a more
expensive masked/control form. The unconditional `min` and full-range loop
together are 1.64-1.81x faster in isolation, more than enough to account for
the retained 1.40x distributed advantage after communication and phase-one/
phase-two work are included.

## Correctness and timing validity

For unsigned distances, assigning
`min(old, dist_ik + dist_kj)` is exactly equivalent to storing the candidate
only when it is smaller. Removing the column subdivision changes traversal,
not operations or dependencies: K remains outer to columns for each row.

Both implementations compute every blocked phase and omit only the path matrix
that is not observable. The retained validation passed internal validation and
external output comparison with the reference distance hash.

Timing begins after an MPI barrier, covers all 128 blocked rounds and
collectives, and ends with an `MPI_MAX` reduction of per-rank elapsed time.
The independent static timing audit classified the run as valid with high
confidence.

## Interpretation

This is a valid hot-loop outlier. A superficially cache-aware extra tile is
counterproductive at the actual local-panel size, while the winner's direct
full-row `min` loop maps more efficiently to AVX2 and is combined with a
cleaner phase-two collective order.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The isolated local updates deliberately omit MPI and are explanatory, not
  replacement benchmark data.
