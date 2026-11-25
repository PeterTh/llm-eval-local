# `unstructured_gpt-6.2-astra-medium_hybrid_r2`

Date: 2026-11-25

## Scope

Hybrid Unstructured, 7,000² elements and 4,000 iterations on four ranks and GPUs.
The 1,846.729 ms median is 15.2% below the previous 2,178.706 ms leader.

## Finding

The generated mesh is a regular grid with zero initial energy and four corner
sources. The implementation uses that structure twice. It stores implicit
neighbors and skips cells outside the expanding corner-influence regions, where
energy remains exactly zero. This is an iteration-dependent reachability bound,
not a floating-point threshold or an early stop.

Eight-row halos let each rank advance up to eight iterations between exchanges,
recomputing successively narrower ghost strips. Each exchange stages the deeper
halo through pinned memory. Interfaces outside the wavefront need no messages.
Energy uses two buffers; cumulative flux is stored once and updated only for
owned cells.

## Close-group comparison

The [previous leader](unstructured_gpt-5.6-sol-low_hybrid_r5.md) updates the full
slab and exchanges one-row halos every iteration. The new strategy trades some
redundant halo computation for fewer exchanges and avoids provably inactive
work early in the simulation.

Astra 6.2 r3 uses the same eight-step, wavefront-limited design and is effectively
tied at 1,848.188 ms. Their ranges overlap at 1,846.044–1,851.771 and
1,843.718–1,852.250 ms. Both are well separated from the older 2,177–2,198 ms
group; the 0.08% ordering within the new pair is not meaningful evidence of a
better implementation.

## Correctness and timing

Complete-array, shape/topology and boundary-sensitive validation passed.
Every iteration executes, missing physical neighbors contribute zero, and ghost
dependencies shrink to the owned domain before the next exchange. Device
synchronization precedes the maximum-rank timing reduction.

## Interpretation

A clear group-level advance through communication batching and specialization
to the generated mesh and initial conditions. It does not demonstrate equal
performance on an arbitrary unstructured graph or initially active full domain.
