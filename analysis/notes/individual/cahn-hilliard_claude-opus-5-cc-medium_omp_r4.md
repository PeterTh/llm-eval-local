# `cahn-hilliard_claude-opus-5-cc-medium_omp_r4`

Date: 2026-10-02

## Scope

OpenMP Cahn–Hilliard, a 512³ grid for 30 steps. The median is 489 ms, versus
540 ms for Opus r5 and 742 ms for Opus r2.

## Finding

The two stencil stages are fused through a small rolling buffer of three
chemical-potential planes. Y/Z tiles retain contiguous X rows. Recomputing the
small tile halo is cheaper than writing and rereading a complete intermediate
field; non-temporal output stores further reduce cache traffic.

This explains a different memory-traffic regime from the older
[Sol 5.6 implementation](cahn-hilliard_gpt-5.6-sol-medium_omp_r2.md), whose median
is 2,265 ms. It does not, by itself, explain the ordering within the new fast pair.

## Close-group comparison

Opus r5 also fuses the stages using three intermediate planes and streaming stores.
It tiles X as well as Y/Z, whereas r4 keeps full contiguous rows within its Y/Z
tiles. Buffer layout, tile dimensions and redundant boundary work are therefore
the relevant distinctions, not the mere presence of fusion.

The 9.4% gap is consistent across tightly separated samples, at 484–493 versus
539–542 ms. The source supports a cache/blocking
explanation, but no ablation identifies which detail supplies that remaining gap.

## Correctness and timing

Retained validation passed. The fused path preserves the clamped boundary behavior
and both update stages. Streaming stores are fenced before dependent work, and the
timer encloses the complete parallel evolution. Memory placement follows the
campaign's NUMA-interleave policy, not an inferred first-touch advantage.

## Interpretation

Fusion explains the fast implementation family; r4's additional lead is a credible
but smaller improvement in how that fused computation is tiled and stored.
