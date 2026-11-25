# `unstructured_gpt-6.2-astra-medium_omp_r4`

Date: 2026-11-25

## Scope

OpenMP Unstructured, 5,000² elements and 134 iterations on 128 cores.
The 821 ms median is 23.0% below the previous leader's 1,066 ms.

## Finding

The static element stores four neighbor indices and a material byte, omitting
the generated edges' invariant unit-flux coefficient. Missing neighbors point
to the cell itself, contributing zero without a boundary branch. A persistent
OpenMP team performs a static SIMD work-sharing loop and one barrier per step.

The important state change relative to the
[previous compact-layout leader](unstructured_gpt-5.6-sol-xhigh_omp_r5.md) is
separating cumulative flux from the ping-pong energy arrays. Flux is never read
from a neighboring cell, so it can accumulate in place. Dynamic storage falls
from four doubles per cell to three: 800 MB to 600 MB at this size. Both versions
already use a roughly 500 MB compact connectivity array. This reduces storage
and avoids carrying flux through a second dynamic buffer, a plausible benefit
in the bandwidth-sensitive loop.

## Close-group comparison

The new range, 817–980 ms, is entirely below the predecessor's 1,062–1,069 ms.
Sol 6.2 r2 and Astra r3 also improve on the old leader, at 916 and 927.084 ms.
Their ranges overlap the slower part of r4's samples, so the precise ordering
among the three new implementations is less secure than their collective
advance. The timings do not separately quantify storage, SIMD or boundary handling.

## Correctness and timing

Complete-array and boundary-sensitive validation passed. Each of the 134 steps
finishes all energy writes before swapping buffers; cumulative flux has one
owning iteration/thread per cell. The timer ends after the parallel region.
The inherited `n_iters - 1` throughput display does not alter the scored elapsed
time or the number of executed steps.

## Interpretation

A substantial improvement within the compact-adjacency design, retaining the
neighbor representation rather than skipping inactive portions of the grid.
