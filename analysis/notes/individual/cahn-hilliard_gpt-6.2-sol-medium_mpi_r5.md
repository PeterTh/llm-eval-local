# `cahn-hilliard_gpt-6.2-sol-medium_mpi_r5`

Date: 2026-11-25

## Scope

MPI Cahn–Hilliard, 256³ cells and 2,000 steps on 128 ranks. Median: 1,292 ms.

## Finding

The implementation uses a three-dimensional Cartesian decomposition, persistent
face exchanges, and interior/boundary overlap for both stencil phases. Once the
chemical-potential phase finishes, concentration can be updated in place: that
second stencil reads neighboring potential values, not neighboring concentration.

## Close-group comparison

This belongs to the same family as the
[Sol 6.1 XHigh leader](cahn-hilliard_gpt-6.1-sol-xhigh_mpi_r4.md).
The nominal 2.1% improvement is small beside overlapping ranges of 1,285–1,333 ms
and 1,305.391–1,359.609 ms. Astra 6.2 r5 follows at 1,327 ms. The samples do not
isolate a benefit from in-place concentration or the communication details.

## Correctness and timing

External and complete-array validation passed. Both stencil phases and their
halo waits execute for every step; the timer reports the maximum rank interval
after a starting barrier. No timing correction was needed.

## Interpretation

A modest new minimum within an established, overlapping group.
