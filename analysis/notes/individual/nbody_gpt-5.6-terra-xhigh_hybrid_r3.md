# `nbody_gpt-5.6-terra-xhigh_hybrid_r3`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `nbody` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used 50,000 bodies
for 30 steps on four MPI ranks and four GPUs. The five times are 1744.604, 1740.221,
1739.388, 1737.937, and 1742.917 ms, with a 1740.221 ms median. The runner-up median
is 1863 ms.

## Finding

Each rank owns one contiguous set of target bodies while all ranks retain the full
position array. After an integration step, `MPI_Allgatherv` refreshes that replicated
array for the next step. The distinctive part is the CUDA force calculation: a
two-dimensional grid decomposes both source tiles and target tiles, so many blocks
compute partial forces concurrently and atomically accumulate them into the target
force arrays. A separate kernel then integrates the local targets.

This adds atomic traffic, but avoids giving a single thread or block the entire
40,000-source loop for each rank-local target. With only one quarter of the targets
available on each GPU, the extra source-tile dimension exposes substantially more
parallel work. The code also omits the final all-gather because no subsequent step
can consume those gathered positions.

## Close-group comparison

The 1863 ms runner-up uses the same MPI ownership, replicated-position model, one
GPU per rank, and final-exchange elimination. Its GPU kernel instead assigns one
thread to a target and makes that thread traverse all shared-memory source tiles.
Thus the two implementations have the same distributed solution shape but genuinely
different intra-GPU parallelization. The winner's 6.6% lower median is large enough
to be credible and is consistent with improved occupancy from the two-dimensional
decomposition.

The next group, near 1989–1993 ms, also uses conventional one-thread-per-target force
kernels. It reinforces that the unusual source-by-target partial-force grid, rather
than a reduced calculation or different MPI semantics, is the main distinguishing
feature.

## Correctness and timing validity

Every rank computes full all-pairs forces for its owned targets in every step. Atomic
partial forces are completed before integration, and all position exchanges needed
by a later step occur. Skipping only the unused final exchange is semantically safe.
The reported time is reduced across ranks with maximum semantics, and retained
validation passed.

## Interpretation

This is a meaningful GPU-kernel win inside an otherwise standard replicated-state
hybrid algorithm. It is not merely the fastest sample from a homogeneous close group.

## Non-decisions

- No generated source or benchmark result is changed.
- No alternative timing or tuning result replaces the retained score.
