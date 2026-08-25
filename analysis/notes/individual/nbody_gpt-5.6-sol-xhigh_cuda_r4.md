# `nbody_gpt-5.6-sol-xhigh_cuda_r4`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place CUDA result in the `nbody` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used 40,000 bodies
for 25 steps. Its five times are 2421, 2410, 2402, 2402, and 2402 ms, giving a
2402 ms median. The immediate runner-up has a 2405 ms median.

## Finding

The implementation stores positions and velocities in structure-of-arrays form and
assigns one warp cooperatively to each target body. Source bodies are staged in
shared memory, each lane accumulates a subset of the source interactions, and warp
shuffle reduction combines those partial forces. Force evaluation and integration
are fused into one kernel per step, with separate position buffers preserving the
required old state.

This is an effective implementation of the full quadratic algorithm: it exposes
lane-level parallelism within each target while retaining enough independent target
warps to fill the GPU.

## Close-group comparison

The 2405 ms runner-up uses the same important decomposition—one warp per target and
structure-of-arrays state—but relies on direct global reads of the source positions,
and batches launches with a CUDA graph. The winner instead tiles the sources through
shared memory and uses ordinary per-step launches. These are distinct memory and
launch strategies built around the same cooperative-work shape.

The 3 ms median difference is 0.1%, and the two five-sample ranges overlap. They
should be treated as a practical tie, not as evidence that shared-memory staging is
intrinsically superior here. The next group, around 2498–2499 ms, commonly assigns
one thread rather than one warp to a target and uses a separately tiled source loop;
that is a different work decomposition, but is still only about 4% slower.

## Correctness and timing validity

All 25 steps and every target-source interaction are executed. The ping-pong position
state prevents in-step updates from changing later force calculations. Device work is
synchronized before the computation time is finalized, and retained internal
validation and external output comparison passed.

## Interpretation

This first place belongs to a close family of sound, fully quadratic GPU solutions.
Its cooperative warp-per-body shape explains membership in the fastest group; the
exact first-place ordering within the leading pair is not statistically meaningful.

## Non-decisions

- No generated source or benchmark result is changed.
- No controlled retuning is substituted for the retained measurement.
