# `nbody_gpt-5.6-sol-xhigh_omp_r3`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place OpenMP result in the `nbody` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used 20,000 bodies
for 100 steps. Its times are 638, 641, 646, 639, and 642 ms, with a 641 ms median.
The runner-up median is 655 ms.

## Finding

The implementation uses structure-of-arrays state and keeps one OpenMP team alive
through the complete time loop. Each worker handles target bodies in blocks of eight.
For a target block, the source-body loop is outermost: one source position is loaded,
then an OpenMP SIMD loop updates eight independent target accumulators. This exposes
packed double-precision square roots and divides while preserving the original source
summation order for each target. Static target assignment and buffer swapping complete
the low-overhead organization.

## Close-group comparison

The 655 ms runner-up has essentially the same solution shape. It also uses
structure-of-arrays storage, a persistent parallel region, static scheduling, blocks
of eight target bodies, and SIMD across those independent targets. The generated
loop details differ slightly, but there is no substantive algorithmic or
parallel-decomposition distinction that explains a robust lead.

The 14 ms median difference is 2.2%, while the observed ranges overlap: the winner
ranges from 638 to 646 ms and the runner-up from 642 to 663 ms. This is best treated
as a close-group first place. A later result around 722 ms uses SIMD reduction across
the source loop for one target at a time. That is a different vectorization shape,
and it is both slower and much more variable in the retained samples.

## Correctness and timing validity

Every force uses all 20,000 source bodies and all 100 steps are executed. Independent
target accumulators avoid races, the team synchronizes at the required worksharing
boundaries, and the timer encloses the persistent computation. Retained internal
validation and external output comparison passed.

## Interpretation

The important result is that vectorizing across a small block of targets is the
fastest observed CPU shape for this cell. The exact ordering of the two implementations
that use that shape is not strong evidence of a unique optimization.

## Non-decisions

- No generated source or benchmark result is changed.
- No controlled rerun replaces the retained measurement.
