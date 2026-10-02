# `cahn-hilliard_claude-opus-5-cc-medium_hybrid_r5`

Date: 2026-10-02

## Scope

Hybrid Cahn–Hilliard, a 512³ grid for 100 steps. The median is 437 ms, followed by
Opus r3 at 451 ms and Sol 6 r2 at 454 ms.

## Finding

Ranks own Z slabs. Two concentration ghost planes allow each GPU to reconstruct
the chemical-potential halo locally, so a step needs one concentration exchange
instead of separate exchanges for concentration and chemical potential. Boundary
work starts early, while streams overlap communication with interior updates; the
interior kernel rolls several Z values through registers.

## Close-group comparison

Opus r3 also uses slabs and overlaps interior work, but performs the two distinct
halo exchanges. That is a concrete communication/computation tradeoff between the
nearest peers. Their samples, 428–445 and 449–459 ms, support a modest 3.1% median
lead, not a fundamentally different scaling regime.

## Correctness and timing

Retained validation passed. Reconstructed halo values use the expanded concentration
neighborhood needed by the two stencil stages. The timed steps finish GPU work and
communicator synchronization before the maximum-rank time is reported.

## Interpretation

A slightly faster member of a close distributed-stencil group, plausibly helped by
exchanging a wider concentration halo instead of communicating two fields.
