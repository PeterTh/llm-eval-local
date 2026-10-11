# `cahn-hilliard_gpt-6.1-sol-xhigh_mpi_r4`

Date: 2026-10-11

## Scope

MPI Cahn–Hilliard, 256³ cells and 2,000 steps on 128 ranks. The median is
1,320.106 ms; Sol 6.1 xhigh r3 follows at 1,338.794 ms.

## Finding

A three-dimensional Cartesian decomposition balances the largest local block
against halo surface area. Persistent requests exchange subarray faces directly
from the two concentration buffers and the chemical-potential buffer. Both
stencil phases compute independent interiors while their halo transfers are
active, periodically calling `MPI_Testall` to drive progress before waiting and
updating the boundary cells.

## Close-group comparison

R3 also uses three-dimensional decomposition and overlap, but packs some faces
and uses ordinary nonblocking requests. Its 1,310.764–1,358.438 ms samples overlap
the winner's 1,305.391–1,359.609 ms. The 1.4% median gap does not isolate a
persistent-request or progress-polling benefit. The
[previous Opus 5 leader](cahn-hilliard_claude-opus-5-cc-medium_mpi_r4.md)
uses a two-dimensional decomposition and nonblocking overlap; its 1,384 ms
median is 4.6% higher than the new winner's.

## Correctness and timing

Native validation and static timing review passed without correction. Each
halo-dependent update waits for its current exchange, both stencil phases run
for all 2,000 steps, and the reported time is the maximum complete rank interval
after a starting barrier.

## Interpretation

A modest improvement within the overlapping-decomposition family. The two new
Sol implementations form a close group; their ordering is not a causal test of
the communication details.
