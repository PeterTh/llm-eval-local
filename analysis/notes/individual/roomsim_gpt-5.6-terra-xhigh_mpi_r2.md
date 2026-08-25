# `roomsim_gpt-5.6-terra-xhigh_mpi_r2`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place MPI result in the `roomsim` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used 5,120 triangles
and 500 time steps on 128 ranks. Its times are 4406, 4449, 4429, 4961, and 4540 ms,
with a 4449 ms median. The immediate runner-up median is 4461 ms.

## Finding

Ranks own contiguous receiver-row ranges and build dense local form-factor and delay
tables. The complete radiosity vector is replicated. Each time step performs the
local weighted propagation followed by `MPI_Allgatherv`, and each rank later computes
correlations for its own receivers before the final gather. Form factors use scalar,
deterministic Monte Carlo sampling and the benchmark's octree intersection machinery.

This is the direct distributed formulation of the reference computation. Its main
strength is a simple row layout with balanced receiver counts and no extra data
redistribution around the dense local loops.

## Close-group comparison

The 4461 ms runner-up uses the same row ownership, dense local tables, replicated
history, and mathematical computation. Its distinctive optimization batches as many
successive time steps as the global minimum propagation delay allows, replacing
per-step collectives with one `MPI_Allgatherv` per batch and then transposing the
rank-major batch buffer. At this problem size, the additional packing, copying, and
bookkeeping offset the reduction in collective count: its simulation phase is
typically slower, while ordinary variation in Monte Carlo precomputation partly
balances the total.

The 12 ms median gap is only 0.27%, and the winner includes a 4961 ms high outlier.
A third result near 4492 ms has faster precomputation but slower simulation. These
results share the same high-level algorithm and data distribution, with different
random-number and exchange schedules; their exact rank order is not separable from
run variation.

## Correctness and timing validity

The winner performs every required per-step exchange, every local dense update, and
the complete correlation. Its timing is reduced with maximum semantics across all
ranks. Retained internal validation and external output comparison passed.

## Interpretation

This should be read as a three-way close group, not as proof that unbatched exchanges
are generally faster. The retained workload happens not to reward the runner-up's
more complicated communication schedule.

## Non-decisions

- No generated source or benchmark result is changed.
- No outlier sample or retained score is altered.
