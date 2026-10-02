# `nbody_claude-opus-5-cc-medium_omp_r4`

Date: 2026-10-02

## Scope

OpenMP N-body, 20,000 bodies and 100 steps. The median is 640 ms, beside 641 ms
for Sol 5.6 xhigh r3 and 645 ms for Opus r1.

## Finding

Structure-of-arrays storage and SIMD across eight targets preserve the source-body
order while parallelizing independent force accumulations. A persistent OpenMP team
separates force calculation from integration with barriers.

## Close-group comparison

The [Sol review](nbody_gpt-5.6-sol-xhigh_omp_r3.md) already explains this design.
Its 638–646 ms range overlaps the winner's 639–645 ms almost completely; Opus r1
spans 636–650 ms. There is no meaningful isolated performance advance to attribute
to the new first-place label.

## Correctness and timing

Retained validation passed. Old positions remain stable during force calculation,
and all iterations and parallel completion fall inside the timer.

## Interpretation

An effective tie within an established implementation family.
