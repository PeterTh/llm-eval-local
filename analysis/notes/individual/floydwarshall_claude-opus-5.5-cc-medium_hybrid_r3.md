# `floydwarshall_claude-opus-5.5-cc-medium_hybrid_r3`

Date: 2026-10-06

## Scope

Hybrid Floyd–Warshall, N=10,240. The median is 90 ms, versus 146 and 147 ms for
the two nearest Opus 5 results. Its 88–90 ms samples form an isolated leading group.

## Finding

The trailing-update kernel combines distance and predecessor-choice information
into one packed integer minimum. Six low bits encode the earliest improving
intermediate vertex; a zero tag lets the existing distance win ties. This replaces
separate per-candidate distance comparisons and path updates with an integer
add/min loop, then writes path entries only for improvements.

Ranks own contiguous groups of 32-row blocks. Each GPU updates 32×128 trailing
tiles with a 4×4 register patch per thread. A high-priority stream advances the
next pivot, while node-shared staging slots and MPI notifications distribute
panels. Lossless narrow encodings reduce input, panel and result traffic; the
complete graph's bounded positive edge weights justify the selected widths.

## Close-group comparison

The [146 ms previous winner](floydwarshall_claude-opus-5-cc-medium_hybrid_r5.md)
already uses node-shared panels and overlapping pivot work. Its 147 ms peer also
packs communicated values. Neither communication overlap nor narrow transfers
alone explains the 38.4% improvement. The packed distance/tie-breaking update,
different tile shape and revised pipeline are substantive source-visible changes.
No ablation partitions their contributions.

## Correctness and timing

Retained validation passed. The packed update preserves strict improvement and
earliest-intermediate tie handling; padding cannot improve real paths.

The original root timer is valid by dependency, not by an explicit `MPI_MAX`:
root starts before publishing input, and peers cannot launch their numerical
work until receiving it or passing the root-participating barrier. Device
synchronization and completed distance gathering precede root's stop. This was
explicitly accepted in the stronger-model timing review. Final path-array
collection is outside the interval under the established timing policy; path
updates themselves occur during computation.

## Interpretation

A strong implementation-level improvement over already optimized peers, with a
specific reduction in the inner-loop bookkeeping. This is not an early local
timer masking other ranks' unfinished work.
