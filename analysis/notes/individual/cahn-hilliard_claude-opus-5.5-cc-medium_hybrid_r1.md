# `cahn-hilliard_claude-opus-5.5-cc-medium_hybrid_r1`

Date: 2026-10-06

## Scope

Hybrid Cahn–Hilliard, 512³ cells and 100 iterations. The median is 387 ms,
followed by Opus 5.5 r5 at 426 ms and r4 at 434 ms.

## Finding

Each rank owns a z slab on one GPU. Two concentration halo planes per side allow
one exchange per step, rather than separate concentration and chemical-potential
exchanges. Boundary updates are issued first; interior updates and the next step's
halo-independent chemical potential overlap host-staged communication.

## Close-group comparison

The nearest peer, r5, also exchanges two-plane concentration halos and overlaps
communication with GPU work. It marches along z in registers, whereas r1 uses
plane kernels and explicitly advances the next chemical-potential interior during
the current exchange. Unit-spacing simplification also removes unnecessary
multiplications in r1's Laplacian. These are concrete scheduling and arithmetic
differences, not proof of separate speedups.

The winner's 385–390 ms range is below r5's 425–428 ms and the
[previous Opus 5 winner](cahn-hilliard_claude-opus-5-cc-medium_hybrid_r5.md),
at 437 ms. The 9.2% lead over the nearest peer is substantial within this tight group.

## Correctness and timing

Retained validation and corrected-source revalidation passed. Every iteration,
halo exchange and GPU completion is included. The corrected report takes the
maximum elapsed time across ranks after the synchronized loop.

## Interpretation

A clearly separated improvement in an established slab/halo design. More overlap
across successive steps is a plausible contributor; no diagnostic isolates it
from the kernel and arithmetic changes.
