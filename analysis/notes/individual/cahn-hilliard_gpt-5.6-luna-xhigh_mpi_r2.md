# `cahn-hilliard_gpt-5.6-luna-xhigh_mpi_r2`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place MPI result in the `cahn-hilliard` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The retained benchmark used a
256-cubed grid for 2,000 iterations on 128 ranks. Its five times are 1407, 1414, 1409,
1418, and 1404 ms, with a 1409 ms median. The next median is 1431.782 ms.

## Finding

The program uses a three-dimensional Cartesian domain decomposition with ghost cells.
It manually packs the six contiguous face buffers, uses persistent MPI requests, waits
for halo completion, and then performs the two complete local seven-point stencil
sweeps. This is a deliberately simple communication and traversal path.

## Close-group comparison

The immediate competitors also use 3-D Cartesian blocks and exchange six faces. Some
instead describe faces with derived datatypes and split the stencil into a core and a
halo-dependent shell so communication can overlap computation. They therefore share
the same overall numerical and decomposition shape but use a genuinely different
communication implementation.

At a 256-cubed global problem over 128 ranks, local blocks are small. The bookkeeping,
datatype traversal, and extra core/shell passes can cost as much as the communication
they hide. The winner's 1.6% median edge is consistent with manual packing and one
straight local traversal, but it is not large relative to the runner's variability.

## Correctness and timing validity

All six neighbor faces are exchanged before dependent cells are evaluated, and both
Cahn--Hilliard stencil phases run for every iteration. Timing starts from an MPI
barrier and is reduced with `MPI_MAX`. Retained internal validation and external
output comparison passed.

## Interpretation

This is a modest communication-engineering win, not a change in the physical method.
The close group shows that direct packing and derived-datatype overlap are competitive;
the simpler path is slightly ahead at this local problem size.

## Non-decisions

- No timing or source correction is proposed.
- No benchmark result or score is changed.
