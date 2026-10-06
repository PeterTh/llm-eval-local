# `stencil3d_claude-opus-5.5-cc-medium_mpi_r5`

Date: 2026-10-06

## Scope

MPI 3D stencil, 256³ cells and 5,000 iterations. The median is 1,161 ms,
followed by Opus 5.5 r1 at 1,200 ms and r3 at 1,231 ms.

## Finding

A three-dimensional Cartesian decomposition minimizes estimated halo traffic.
Persistent send/receive requests and subarray datatypes are prepared for both
alternating buffers. Each iteration starts the exchanges, computes the independent
interior, waits for halos, then updates the outer shell.

## Close-group comparison

R1 uses a two-dimensional y/z decomposition, leaving x rows whole, and issues
ordinary nonblocking requests each step. Both overlap communication with interior
work. The winner's 1,159–1,205 ms samples overlap r1's 1,173–1,208 ms, so the
3.3% median difference does not isolate a persistent-request advantage.
Both improve on the
[previous Sol result](stencil3d_gpt-5.6-sol-xhigh_mpi_r1.md), at 1,318 ms.

## Correctness and timing

Validation and corrected-source revalidation passed. Every halo-dependent shell
waits for its current exchange; all 5,000 steps and the final synchronization are
timed. The corrected report takes the maximum elapsed time across active ranks.

## Interpretation

A new fast decomposition/exchange group with overlapping leading samples, rather
than a firmly established ordering between r5 and r1.
