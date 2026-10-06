# `nbody_claude-opus-5.5-cc-medium_omp_r3`

Date: 2026-10-06

## Scope

OpenMP N-body, 20,000 bodies and 100 steps. The median is 616 ms; the other
Opus 5.5 repetitions occupy 624–634 ms, ahead of the previous 640 ms winner.

## Finding

Eight target bodies share each source-body load and map to independent SIMD
lanes. Double-buffered structure-of-arrays positions let each target's force,
velocity and new position be computed together, leaving one OpenMP barrier per
step instead of separate force and integration phases.

## Close-group comparison

The [previous Opus review](nbody_claude-opus-5-cc-medium_omp_r4.md) covers the
same eight-target SIMD family. Fusing integration is a useful scheduling
refinement, but the new winner is only 1.3% below r4's 624 ms median. The results
support a modestly faster group, not a large isolated advance by r3.

## Correctness and timing

Retained validation passed. Every force calculation reads the old position
buffer; it is exchanged only after the step barrier. All 100 steps, layout
conversion and parallel completion are timed.

## Interpretation

A small improvement within an established SIMD design, with less synchronization
between force calculation and integration.
