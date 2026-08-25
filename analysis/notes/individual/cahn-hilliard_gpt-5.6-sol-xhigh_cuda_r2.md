# `cahn-hilliard_gpt-5.6-sol-xhigh_cuda_r2`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place CUDA result in the `cahn-hilliard` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 512-cubed grid
for 259 iterations. Its five times are 2485.036, 2485.193, 2490.492, 2493.888, and
2496.099 ms, with a 2490.492 ms median. The runner-up median is 2516.644 ms.

## Finding

The winner performs the conventional two global-memory stencil passes per time step:
one computes chemical potential and one updates concentration. The launches are
captured in a CUDA graph, and a 32 x 4 x 2 block keeps X accesses coalesced. For this
known 512-cubed domain it specializes indexing to 32-bit arithmetic, reducing address
calculation cost in the two bandwidth-heavy kernels.

## Close-group comparison

The immediate runner uses the same two-pass algorithm, the same block shape, and the
same CUDA-graph organization, but carries wider `size_t` index arithmetic. The 1.0%
gap is consistent with that small instruction-count difference, although it remains
close enough that exact rank ordering is not a strong result.

Other implementations use shared-memory X/Y tiles. That is a genuinely different
kernel approach, but for this seven-point stencil the extra cooperative loads and
synchronization do not beat the simple coalesced global-memory kernels. Thus the very
closest pair has the same solution shape; the wider fast group includes a different
tiling approach.

## Correctness and timing validity

Every iteration executes both required stencil passes with ping-pong state. CUDA event
timing covers the captured computation and waits for completion. Retained internal
validation and external output comparison passed.

## Interpretation

This is a small implementation-level win within the dominant direct-stencil design,
not an algorithmic outlier. The useful observation is that compact index arithmetic
and a simple global-memory kernel slightly outperform shared-memory tiling here.

## Non-decisions

- No generated source or benchmark result is changed.
- No controlled retuning is substituted for the retained measurement.
