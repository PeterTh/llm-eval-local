# `nbody_claude-fable-5.1-cc-medium_omp_r4`

Date: 2026-11-08

## Scope

OpenMP N-body, 20,000 bodies and 100 steps: 613 ms, versus 616 ms for Opus 5.5 r3.

## Finding

Target bodies occupy SIMD lanes while source bodies are visited in order.
Double-buffered position arrays permit force calculation and integration to
share one persistent team with one worksharing barrier per step. At this size,
Fable uses 16-target blocks and dynamic block scheduling.

## Close-group comparison

This is the same broad design as the
[previous winner](nbody_claude-opus-5.5-cc-medium_omp_r3.md), which uses eight-target
blocks. Samples are 612–614 versus 614–617 ms; Sol 6.1 XHigh r5 follows at 622 ms.
The 0.5% median lead does not establish a meaningful architectural separation.

## Correctness and timing

Native validation, shape checks and full-array comparison passed. The timer
includes the initial position gather, every simulation step and the final team
completion. No timing correction was needed.

## Interpretation

A narrow new leader of the existing target-vectorized, double-buffered group.
