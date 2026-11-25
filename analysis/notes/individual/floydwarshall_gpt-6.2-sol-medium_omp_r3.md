# `floydwarshall_gpt-6.2-sol-medium_omp_r3`

Date: 2026-11-25

## Scope

OpenMP Floyd–Warshall, 8,704 nodes on 128 cores. The 573 ms median is 44.0% below
the previous leader's 1,024 ms, with ranges of 571–573 and 1,009–1,030 ms.

## Finding

The implementation processes 64-wide pivot blocks within a persistent OpenMP
team. Saved pivot rows are packed by destination tile, and saved columns retain
the values that the serial pivot ordering would consume. Independent trailing
tiles can then replay those inputs locally.

It also avoids relaxations that cannot improve any destination in a tile row.
For each pivot, the source-to-pivot distance plus the minimum saved pivot-row
distance is a lower bound on every candidate. If that bound is no smaller than
the output row's maximum distance, the pivot cannot improve any entry. Distances
only decrease, so the initial maximum remains a safe, possibly loose bound.
A 64-bit candidate mask skips such pivots; remaining pivots are processed in
ordered pairs with SIMD updates and first-pivot tie preference.

## Close-group comparison

The [Opus 5 predecessor](floydwarshall_claude-opus-5-cc-medium_omp_r4.md) already
uses 64×64 blocking and packed panels. The new gain is therefore not simply
blocking versus an unblocked implementation. Sol 6.2 r4 and r5 follow at 720 and
858 ms, also below the old winner.

In a [paired diagnostic](../2026-11-25-gpt62-outlier-probes.json), retaining every
pivot while leaving the other machinery intact increased the median from 620
to 1,343 ms. The three measured samples per mode followed separate warm-ups and
alternated execution order. This isolates pruning as a substantial contributor;
the diagnostic baseline is distinct from the retained 573 ms measurement.

## Correctness and timing

Integer-output and shape validation passed. The diagnostic modes also produced
identical result blocks for a 257-node graph with partial tiles. The timer includes
scratch allocation, packing, pruning and all three blocked phases. Reported GOPS
uses the nominal cubic workload, not a count of the relaxations actually executed.

## Interpretation

A valid reduction in unnecessary work, especially effective once short paths
leave few possible improvements in this dense positive-weight graph.
