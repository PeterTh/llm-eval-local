# `stencil3d_gpt-6.1-sol-xhigh_mpi_r4`

Date: 2026-10-11

## Scope

MPI 3D stencil, 256³ cells and 5,000 iterations on 128 ranks. The median
is 1,080.983 ms, 6.9% below the previous best at 1,161 ms.

## Finding

The source chooses a three-dimensional Cartesian decomposition using a cost
that combines the largest local block with halo area, penalizing the strided
x face more heavily. Persistent requests exchange subarray faces directly from
both alternating buffers. Independent interior updates periodically call
`MPI_Testall` for communication progress; a final wait precedes six disjoint
boundary regions. Contiguous x traversal and restrict-qualified pointers make
the interior loops amenable to vectorization.

## Close-group comparison

The [previous Opus 5.5 leader](stencil3d_claude-opus-5.5-cc-medium_mpi_r5.md)
already combines three-dimensional decomposition, persistent requests and
subarray datatypes. It computes the whole independent interior before waiting,
rather than periodically polling. Its 1,159–1,205 ms samples do not overlap the
new winner's 1,068.181–1,114.619 ms; the next Sol 6.1 result is at 1,203 ms.
This is a meaningful moderate separation, not just a new ordering within
overlapping samples. The topology heuristic and progress polling are plausible
contributors, but source comparison alone does not isolate either one.

## Correctness and timing

Native validation and static timing review passed without correction. Fixed
global boundaries are initialized in both buffers and left unchanged. All
5,000 stencil steps and their halo dependencies are inside the per-rank timer,
with a starting barrier and `MPI_MAX` report. Opus also times a closing barrier;
that minor boundary difference prevents attributing the entire gap to the
stencil or exchange implementation alone.

## Interpretation

A faster implementation of the same overlap-and-persistent-halo family. The
retained samples support a lead at this configuration, without establishing a
general advantage for a particular decomposition or MPI progress strategy.
