# `floydwarshall_gpt-6.2-sol-medium_mpi_r4`

Date: 2026-11-25

## Scope

MPI Floyd–Warshall, 8,192 nodes on 128 ranks. The median is 543 ms, 30.8% below
the previous 785 ms leader; the ranges are 541–567 and 784–805 ms.

## Finding

A two-dimensional block-cyclic grid distributes 32-wide pivot blocks. Each block
saves the row and column values used at the corresponding serial pivot, broadcasts
the panels, then updates independent output tiles with contiguous 128-column
chunks and 16-row groups.

The distinctive inner loop encodes distance and pivot preference together in
16 bits: distance occupies the upper bits, while the low six bits order equal
distances by their first improving pivot. The existing value gets tie priority.
An integer minimum therefore selects both the distance and path decision, with
the final distance/path stores performed after the block's pivot reduction.

This is exact for the generated positive, fully connected graph. Its original
distances are at most 201, can only decrease, and even the sum of two such
distances plus the pivot code fits comfortably in 16 bits. It is a
benchmark-specific representation, not a general bound for arbitrary graphs.

## Close-group comparison

The [previous Sol 5.6 leader](floydwarshall_gpt-5.6-sol-xhigh_mpi_r5.md) uses
32-bit distances and a direct unconditional-min loop, without observable path
storage. The new run achieves its improvement while maintaining path decisions.

Sol 6.2 r3 is another clear advance at 591 ms, but uses a different compact
representation: byte distances and saturating AVX2 addition, with path updates
only for changed lanes. Its 586–602 ms range is separate from r4's. Both exploit
the small generated distance range; their ordering does not isolate representation
width from tiling and update structure.

## Correctness and timing

Integer-output and shape/topology validation passed. Saved pivot inputs preserve
ordered dependencies and strict-improvement ties. Panel preparation, collective
waits and all blocked updates are inside a barrier-started, maximum-rank timer.

## Interpretation

A separated improvement from compact arithmetic and cache-local blocked updates.
The result demonstrates effective use of this workload's value bounds, rather
than a universal advantage of narrower Floyd–Warshall storage.
