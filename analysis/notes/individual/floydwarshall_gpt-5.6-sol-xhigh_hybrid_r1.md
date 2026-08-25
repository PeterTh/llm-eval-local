# `floydwarshall_gpt-5.6-sol-xhigh_hybrid_r1`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `floydwarshall` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 10,240-vertex
graph on four MPI ranks and four GPUs. Its five times are 467, 455, 450, 490, and 466
ms, with a 466 ms median. The next medians are 470 and 485 ms.

## Finding

All leading programs use blocked Floyd--Warshall with 32 x 32 tiles. Contiguous tile
rows are distributed across ranks, the rank owning the pivot broadcasts its 32-row
pivot slab each round, and each GPU performs the dependent phase-two and phase-three
updates for its local tiles.

The winner stores and updates only the distance matrix. It does not retain the optional
path/predecessor matrix because that state is not part of the required result. Its GPU
kernel maps one thread to one output element in a 32 x 32 tile.

## Close-group comparison

The 470 and 485 ms implementations use the same distributed tile-row algorithm and
pivot communication, but retain path updates and commonly have each thread update a
short vertical strip. Some also double-buffer pivot staging. They therefore share the
same global solution shape but do extra state work and use a different GPU microkernel.
The winner's modest advantage is consistent with omitting the unobserved path matrix.

The first two sample ranges overlap, so the exact four-millisecond ordering is not
stable even though the reduced-state design is structurally leaner.

## Correctness and timing validity

Every distance tile participates in all blocked pivot rounds. Omitting path state does
not change shortest-path distances, which are the validated output. Each phase is
synchronized and the reported time is the maximum across ranks. Retained internal
validation and external output comparison passed.

## Interpretation

This is a valid reduced-state optimization within a common distributed blocked design.
It is not evidence for a different shortest-path algorithm, and its small rank-one
margin remains within ordinary run variation.

## Non-decisions

- No generated source or retained result is changed.
- No score or output requirement is redefined.
