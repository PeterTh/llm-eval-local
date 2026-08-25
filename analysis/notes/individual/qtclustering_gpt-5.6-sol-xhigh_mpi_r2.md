# `qtclustering_gpt-5.6-sol-xhigh_mpi_r2`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains why this run is an extreme first-place result in the
`qtclustering` MPI cell. It refers to data release
`local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used 4,000 points on 128 MPI ranks. Its five reported
clustering times are 31, 29, 30, 29, and 31 ms, giving a median of 30 ms. The
next-fastest successful result has a median of 223 ms, so the gap is 7.43x.

## Finding

The result comes from removing work from the greedy candidate construction,
not from reporting one favorable rank.

For each seed, the implementation first builds the subset that is within the
threshold of that seed. It stores squared distances, avoiding square roots,
and thereafter visits only this compact eligible set. When a new member is
selected, each candidate's maximum distance is updated using only that member.
Candidates that cross the threshold are removed permanently because their
diameter can only increase.

The runner-up also performs an incremental diameter update, but it computes
Euclidean square roots and scans all 4,000 point slots at every greedy step,
including slots already marked ineligible. The difference becomes larger in
later outer rounds: the winner scans the shrinking unclustered and eligible
sets, whereas the runner-up retains a fixed-size scan.

The winner also detects the final all-singleton state and emits the remaining
singletons without one MPI collective per point. For this input, that shortcut
replaces the last 14 singleton rounds. It is helpful but not the principal
source of the 7.43x gap.

## Controlled evidence

The two exact first-round candidate kernels were benchmarked independently on
the generated 4,000-point input. Five complete evaluations of every seed took
1.212-1.220 s for this implementation and 4.470-4.481 s for the runner-up,
a 3.67x kernel advantage. Both produced the same aggregate candidate
cardinality, 290,101 per pass.

A separate execution of the winner's outer algorithm found 142 non-singleton
clusters followed by 14 singletons. This confirms both that the suffix shortcut
is exercised and that most of the advantage must come from the compact,
squared-distance candidate kernel. The growing difference between compact and
fixed-size scans in later rounds plausibly accounts for the larger full-run
ratio.

## Correctness and timing validity

Squared-distance comparisons preserve the strict threshold and tie rules.
Incremental maxima are equivalent to rescanning all members, and permanently
discarding an over-threshold candidate is valid because adding members cannot
reduce a cluster diameter. The singleton suffix is also exact: removing points
cannot turn a singleton candidate into a larger one.

The retained validation passed internal validation and external output
comparison. Timing starts after an MPI barrier and covers all distributed
candidate evaluations, winning-member broadcasts, and active-set updates. Each
rank measures its elapsed time, and rank zero reports an `MPI_MAX` reduction.
The independent static timing audit classified the timer as valid with high
confidence.

The 30 ms measured region is short relative to the approximately 11 s process
wall time and is quantized to integer milliseconds. It should not support fine
comparisons, but the stable 29-31 ms range, 7.43x gap, and independent kernel
experiment make the first-place explanation robust.

## Interpretation

This is a valid algorithmic outlier rather than an MPI timing artifact. The
score reflects aggressive pruning of the dominant greedy search. It is a
compute-kernel result; MPI launch and setup dominate end-to-end wall time.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The isolated kernel measurements are explanatory evidence, not replacement
  benchmark data.
