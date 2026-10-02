# `stencil3d_claude-opus-5-cc-medium_hybrid_r2`

Date: 2026-10-02

## Scope

Hybrid 3D stencil, a 384³ grid for 2,800 steps. The median is 1,463 ms, versus
2,866 ms for Opus r4 and 2,873 ms for GPT-5.2 r4.

## Finding

Ranks own Z slabs. Boundary planes are computed and staged early for halo exchange
while the GPU processes the interior. The bulk kernel uses 64×4 threads, rolls
Z-neighbor values through registers and obtains X/Y neighbors through cached loads.
Each block handles a 32-plane Z segment, exposing additional blocks along Z without
block-wide barriers inside that bulk sweep.

Node-shared MPI windows, double-buffered halos and CUDA events overlap the exchanges
with useful work. Division by seven uses a refined multiply/FMA sequence.

## Close-group comparison

Those last communication and arithmetic features are also present in Opus r4.
They cannot by themselves explain why its median is almost twice as large.
The important visible kernel contrast is r4's shared-memory X/Y tile: it uses
32×8 threads, traverses a whole slab per block and performs two block barriers for
each Z plane. The winner trades that explicit shared-memory reuse for register
rolling, cached neighbor loads and more independent Z segments.

The 1,461–1,465 versus 2,862–2,870 ms ranges show a stable, substantial gap.
Reduced barrier cost and different block scheduling are credible explanations,
but no ablation assigns the near-twofold gain to either. The
[older GPT-5.2 review](stencil3d_gpt-5.2_hybrid_r4.md) remains useful broader context,
not a substitute for comparing these two closely related Opus designs.

## Correctness and timing

Retained validation passed. Fixed physical boundaries are preserved in both
ping-pong buffers; halo completion precedes dependent updates. The corrected
interval covers all 2,800 steps, starting before synchronization and ending after
device completion and the world barrier. This single-node result does not test
the separate inter-node communication path.

## Interpretation

A strong GPU stencil-kernel outlier inside a shared overlapped communication design.
The review attributes the candidate cause to the actual nearest-peer differences,
not to shared-memory MPI or fast division that both programs already use.
