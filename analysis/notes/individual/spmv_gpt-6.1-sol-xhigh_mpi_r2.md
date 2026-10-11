# `spmv_gpt-6.1-sol-xhigh_mpi_r2`

Date: 2026-10-11

## Scope

MPI SpMV, 10,000 rows, approximately 2.5 million nonzeros and 50,000
iterations on 128 ranks. The median is 1,174.162 ms, 15.0% below the
previous best at 1,381.833 ms.

## Finding

The distinguishing inner loop interleaves four CSR rows. Four independent
double-precision accumulators advance together through their common length,
then finish their individual tails. This exposes independent loads and
arithmetic while retaining each row's original accumulation order. The source
explicitly disables floating-point contraction.

The surrounding distributed method is conventional: contiguous whole-row
partitions balance nonzeros and row overhead, 32-bit indices keep local CSR
metadata compact, and every rank holds the unchanged input vector. Each of the
50,000 iterations processes all local nonzeros, without communication inside
the repeated local calculation.

## Close-group comparison

The [previous Terra leader](spmv_gpt-5.6-terra-xhigh_mpi_r4.md)
uses a scalar row-at-a-time loop with restrict-qualified arrays and similar
nonzero-balanced partitioning. Other new Sol results cluster near 1,415–1,427 ms.
The winner's 1,162.206–1,202.972 ms samples are clearly separated from the
previous leader's 1,377.341–1,386.340 ms, warranting a targeted diagnostic.

The [bounded diagnostic](../2026-10-11-sol61-spmv-diagnostic.json) changes
only the timed call from the four-row routine to the source's existing scalar
CSR routine, keeping partitioning, inputs, compiler flags, timer and resource
profile fixed. After one warmup per variant, three alternating-order samples
give 1,195.279 ms for the original and 1,417.597 ms for the scalar variant—a
15.7% reduction. All original samples (1,165.072–1,202.916 ms) are below all
scalar samples (1,414.910–1,428.834 ms). This supports row interleaving as the
main explanation for the lead; it does not isolate every instruction-level
effect of compiling the two routines.

## Correctness and timing

Native validation and static timing review passed without correction. A starting
barrier precedes all repeated products, and the report takes `MPI_MAX` over the
complete per-rank intervals. Gathering the result follows measurement.

Both diagnostic variants passed their internal sequential checks and the
unchanged numerical comparator at the full matrix size with one iteration.
The ten diagnostic executions are separate evidence, not replacement benchmark
samples or a new validation policy. The published five measurements and scores
are unchanged.

## Interpretation

A supported implementation-level outlier: independent row accumulators reduce
the cost of the cache-friendly local CSR loop. This is not a reduction in
required iterations, a timing shortcut, or evidence of a generally different
distributed SpMV algorithm.
