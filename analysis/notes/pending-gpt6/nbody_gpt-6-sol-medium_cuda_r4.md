# `nbody_gpt-6-sol-medium_cuda_r4`

Date: 2026-10-02

## Scope

CUDA N-body, 40,000 bodies and 25 steps. The median is 2,401 ms, beside 2,402 and
2,405 ms for Sol 5.6 xhigh r4 and r2.

## Finding

A warp cooperates on each target body. Its lanes visit source bodies at stride 32,
reduce forces with warp shuffles, and let lane zero integrate the result. Separate
input and output body arrays are swapped between steps.

## Close-group comparison

The [previous winner's review](../individual/nbody_gpt-5.6-sol-xhigh_cuda_r4.md)
already describes this fast warp-per-target group. That implementation uses
structure-of-arrays storage and shared source tiles; this one uses body structs
and direct global reads. The alternative r2 also uses direct reads.
One millisecond at a roughly 2.4-second runtime, with whole-millisecond reporting,
does not distinguish these designs convincingly.

## Correctness and timing

Retained validation passed. Each step reads old positions and writes a separate
buffer, avoiding an in-place force/integration race. This timer includes initial
upload, all steps and the blocking final download; the previous winner's CUDA-event
interval covers device computation alone.

## Interpretation

A nominal new winner in an existing near-tied group, not evidence of a new
algorithmic advantage.
