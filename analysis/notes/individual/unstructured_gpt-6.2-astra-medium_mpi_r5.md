# `unstructured_gpt-6.2-astra-medium_mpi_r5`

Date: 2026-11-25

## Scope

MPI Unstructured, 2,000² elements and 5,000 iterations on 128 ranks.
Median: 308.101 ms, versus the previous 323.088 ms leader.

## Finding

A two-dimensional Cartesian partition uses three arrays: ping-pong energy and
in-place cumulative flux. Nonblocking face exchanges overlap the independent
interior update; derived datatypes handle strided columns. Physical-boundary
ghosts mirror the adjacent cell, making a missing edge contribute zero.

## Close-group comparison

The [previous Sol 5.6 leader](unstructured_gpt-5.6-sol-xhigh_mpi_r1.md) has the
same compact-state, overlapped Cartesian design, but uses persistent requests.
The new 290.362–323.063 ms range overlaps its 318.661–335.374 ms range. Other
nearby medians are 326 and 326.005 ms. The 4.6% nominal improvement does not
establish a causal benefit from replacing persistent communication.

## Correctness and timing

Complete-array and boundary-sensitive validation passed. All owned cells and
iterations are computed; perimeter updates wait for their halos. The complete
simulation is timed after a barrier and reduced to the rank maximum.

## Interpretation

A new minimum within the established close group, using the regular topology
of this generated “unstructured” workload.
