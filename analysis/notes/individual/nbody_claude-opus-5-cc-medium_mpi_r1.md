# `nbody_claude-opus-5-cc-medium_mpi_r1`

Date: 2026-10-02

## Scope

MPI N-body, 40,000 bodies and 100 steps. The median is 2,534 ms, followed by
Opus r4 at 2,582 ms and Astra 6 r2 at 2,583 ms.

## Finding

Each rank integrates a contiguous target range against replicated positions.
Four target bodies are evaluated together with SIMD/FMA while source bodies are
visited in ascending order. Velocities remain local; positions are all-gathered
after each step.

## Close-group comparison

Opus r4 uses the same four-target blocking and broadly the same data organization.
The [older Sol review](nbody_gpt-5.6-sol-xhigh_mpi_r1.md) discusses the surrounding
direct-interaction group. Here the leading three medians are within 1.9%; r1's
2,530–2,545 ms samples sit just below r4's 2,577–2,591 ms. Minor kernel and layout
details are plausible contributors, not a change in asymptotic work.

## Correctness and timing

Retained validation passed. Every target visits all sources, and each position
all-gather completes before the next force evaluation. All steps and position
collectives are covered by the maximum-rank interval; final velocity output is not.

## Interpretation

A small, consistently observed lead in a close SIMD-across-targets MPI group.
