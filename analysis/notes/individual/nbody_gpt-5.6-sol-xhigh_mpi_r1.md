# `nbody_gpt-5.6-sol-xhigh_mpi_r1`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains why this run is substantially faster than the other successful MPI
results in the `nbody` cell. It refers to data release `local-eval-2026-08-25` at data
commit `f83773e`.

The retained benchmark used 40,000 bodies for 100 simulation steps on 128 MPI ranks.
Its five reported simulation times are 2753, 2734, 2741, 2747, and 2762 ms, giving a
median of 2747 ms. The next-fastest successful result has a median of 4671 ms, while
the main group of conventional implementations is near 5930 ms.

## Finding

The advantage is caused by vectorizing across four independent target bodies. A
conventional direct N-body kernel completes the full source-body loop for one target
at a time. Each force accumulator then has a loop-carried floating-point dependency,
which prevents strict-semantics vectorization across source bodies.

This implementation instead holds four targets and their independent force
accumulators at once. For each source body, it computes the interaction with all four
targets. The compiler can therefore use four-wide AVX2 packed double-precision square
root and division instructions without changing the source summation order for any
target. It also loads each source position once for four interactions. Generated
assembly inspection confirms packed `vsqrtpd` and `vdivpd` instructions in the force
kernel.

The build enables `-fno-math-errno`, which permits direct vector square-root code
generation without enabling unsafe fast-math transformations. Restrict-qualified
arrays make the lack of aliasing explicit. The MPI distribution is aligned to
four-body blocks, so the 40,000-body benchmark assigns 316 bodies to the first 16
ranks and 312 to the remaining 112 ranks. Every local count is divisible by four,
avoiding the scalar cleanup path while keeping load imbalance to about 1.3%.

No other successful implementation inspected in this MPI cell uses the same
multi-target blocking pattern.

## Controlled evidence

The exact force function was benchmarked independently with 40,000 source bodies,
the busiest rank's 316 target bodies, and 100 repetitions. Temporary variants changed
only the target block size:

| Target block | Kernel time |
|---:|---:|
| 1 | 5.483 s |
| 2 | 4.763 s |
| 4 | 2.474 s |
| 8 | 2.423 s |

Moving from one to four targets gives a 2.22x kernel speedup. This closely accounts
for the ratio between this run's 2747 ms median and the approximately 5930 ms medians
of conventional full MPI implementations. The eight-target version provides little
additional benefit because the processor's native AVX2 double-precision vector width
is four; it mainly processes two four-wide vectors.

## Correctness and timing validity

The decomposition still evaluates every ordered target/source interaction in every
simulation step. Each target accumulates sources in the original order, after which
the owning rank integrates its bodies and participates in the position all-gather.
The retained validation run passed internal validation and external output comparison.

Timing begins after an MPI barrier. It includes all 100 force computations,
integrations, and position all-gathers. Each rank measures its own elapsed time, and
rank zero reports an `MPI_MAX` reduction, so the value is the slowest-rank makespan
rather than a favorable local rank. The five measurements' 28 ms total range further
shows that the result is stable. The independent static timing audit classified this
run as valid with high confidence and found no timing issue.

## Interpretation

This is a valid SIMD-kernel performance outlier rather than an MPI timing artifact.
Its approximately 2.16x advantage over conventional implementations comes from
restructuring the dominant all-pairs force calculation into the vector width of the
evaluated CPU while preserving the direct N-body algorithm.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The isolated kernel experiment is explanatory evidence, not a replacement benchmark.
