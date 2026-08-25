# `qtclustering_gpt-5.6-sol-xhigh_omp_r3`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place OpenMP result in the `qtclustering` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used 6,200 points and
the default diameter threshold. Its five times are 122, 128, 131, 132, and 133 ms,
with a 131 ms median. The immediate runner-up median is 133 ms.

## Finding

The implementation avoids rebuilding and rescanning every candidate cluster from
scratch. For each seed it stores every candidate's current maximum distance to any
accepted member. When a new member is added, only the distance to that newest member
must be evaluated. A candidate is removed permanently as soon as its running maximum
reaches the threshold. Thread-local candidate storage is reused, and one persistent
OpenMP team evaluates seeds with guided scheduling before a deterministic reduction
selects the best cluster.

That incremental running-maximum invariant removes most repeated distance work and
is the primary reason this result is far ahead of conventional implementations.

## Close-group comparison

The 133 ms runner-up uses the same fundamental incremental candidate algorithm and
the same permanent-pruning rule. It differs in orchestration: it allocates candidate
and maximum-distance storage for each seed, enters a new parallel region for each
cluster-selection round, records cluster cardinalities during the parallel search,
and then reconstructs the winning cluster. Those choices add overhead, but the
dominant pruned distance scans are the same.

The two medians differ by only 1.5% and their sample ranges overlap, so they are a
practical tie built from the same solution shape. The next result, at 203 ms,
precomputes the full pairwise distance matrix and uses neighborhood lists. That is a
genuinely different approach: it is still much faster than the conventional
1599 ms result, but its up-front quadratic matrix work makes it slower than the
incremental pair.

## Correctness and timing validity

Candidate removal follows directly from the monotonic maximum-distance criterion;
an excluded candidate can never become eligible later. Seed results are reduced with
the required deterministic tie handling. The timer covers all clustering rounds, and
retained internal validation and external output comparison passed.

## Interpretation

The large cell-level advantage belongs to the incremental pruning algorithm. The
specific first-place rank within the two implementations of that algorithm is not a
meaningful performance distinction.

## Non-decisions

- No generated source or benchmark result is changed.
- No alternative measurement replaces the retained score.
