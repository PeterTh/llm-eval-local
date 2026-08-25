# `qtclustering_gpt-5.6-sol-xhigh_hybrid_r2`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the first-place outlier in the `qtclustering` hybrid cell
for data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used 5,000 points on four MPI ranks, with one RTX 3090
and 32 OpenMP cores per rank. Its times are 169, 167, 169, 169, and 168 ms,
giving a median of 169 ms. The next result has a 263 ms median, a 1.56x gap.

## Finding

The principal advantage is amortizing pairwise distance calculation across the
many repeated QT seed evaluations.

Each rank constructs a dense 5,000 x 5,000 distance matrix on its GPU. Seed
evaluation then loads precomputed distances while incrementally maintaining
each candidate's maximum diameter and retiring infeasible candidates. CUDA
blocks evaluate seed batches, OpenMP reduces returned cardinalities on the
host, and MPI `MAXLOC` selects the global cardinality/lowest-seed winner.

The runner-up uses the same high-level distributed decomposition and an
incremental candidate algorithm, but computes squared point distances in the
CUDA hot loop. That avoids square roots for any one comparison, yet the same
point pairs are revisited across many seeds, greedy additions, and outer
clustering rounds.

The dense matrix costs about 191 MiB per GPU and is computed once. For the
deterministic 5,000-point input, only 3.88% of possible non-self pairs are
within the initial threshold, but the greedy algorithm still performs many
distance checks before candidates are retired. Reusing one matrix load instead
of repeating coordinate arithmetic across all those evaluations wins despite
the precomputation cost.

## Comparative evidence

The comparison is conservative in favor of the runner-up. This winner creates
its CUDA evaluator and builds the distance matrix inside the measured region.
The runner-up constructs its evaluator and allocates its scratch state before
starting its timer. Even with approximately 25 million square roots and the
matrix allocation included, the winner reports 167-169 ms rather than
261-264 ms.

Both implementations use device-resident clustered state and batched seed
evaluation. Their clearest algorithmic difference in the measured critical
path is therefore precomputed versus repeatedly calculated distances. A live
GPU ablation was not possible in this side-session sandbox because the driver
was unavailable; the retained comparison and exact timing-boundary inspection
are the causal evidence.

## Correctness and timing validity

The matrix stores the same Euclidean distance used by the greedy algorithm.
Incremental maximum updates, strict threshold comparison, and lower-index tie
breaking preserve candidate construction. The retained validation passed
internal validation and external output comparison.

Timing starts after an MPI barrier, includes evaluator construction, distance
precomputation, all CUDA/host/MPI clustering rounds, and a final device
synchronization. Each rank reports local elapsed time and rank zero records an
`MPI_MAX` reduction. The independent static timing audit classified the run
as valid with high confidence.

## Interpretation

This is a valid precomputation-amortization outlier, not a favorable-rank
measurement. It wins by recognizing that QT clustering reuses pairwise
distances enough to repay a dense matrix build even at this problem size.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The input census and static comparison are explanatory evidence, not
  replacement benchmark data.
