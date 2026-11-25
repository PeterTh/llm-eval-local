# `roomsim_gpt-6.2-sol-medium_hybrid_r1`

Date: 2026-11-25

## Scope

Hybrid Roomsim, 5,120 triangles and 2,000 steps on four ranks and GPUs.
The 520 ms median is 22.0% below the previous eligible leader's 667 ms.

## Finding

Ranks own contiguous receiver rows. Form-factor preprocessing preserves the
reference MT19937 stream: culled-pair masks determine draw counts, an MPI prefix
sum finds each rank's starting position, and jump-ahead/checkpoint machinery
supplies GPU tiles with the corresponding random words. GPU ray traversal uses
the flattened octree rather than replacing visibility tests with a simpler model.

Propagation exploits the smallest positive delay. Steps are grouped into batches
of at most eight, small enough that every dependency crosses a batch boundary.
Only new radiosity samples are exchanged through host-staged `MPI_Allgatherv`.
A 64-step remote-history ring covers the room's bounded propagation delay;
complete local and source histories remain available for correlation. Independent
correlation lags run in parallel while each lag retains its time-order sum.

## Close-group comparison

The [previous Sol 5.6 Medium leader](roomsim_gpt-5.6-sol-medium_hybrid_r2.md)
exchanges every step and searches correlation lags serially per receiver.
Its root-reported phase medians are 240/351/76 ms for preprocessing, propagation
and correlation, versus 253/261/6 ms here. These local phase diagnostics point
to propagation and correlation, not cheaper preprocessing, as the source of the
overall improvement; the scored total is maximum-rank wall time.

Sol 6.2 r3 and r5 follow at 567 and 599 ms. The winner's 516–523 ms range is
clearly separated from the old leader's 661–674 ms range.

## Correctness and timing

Complete-array validation and timing-corrected revalidation passed. Ray sums,
emitter accumulation and first-lag tie handling preserve their required order.
The corrected total spans preprocessing through gathered distances and reduces
the complete interval to its rank maximum; asynchronous GPU work is completed
within those phases.

## Interpretation

A substantial improvement within the distributed-GPU family, combining fewer
propagation exchanges with much more parallel correlation. The fixed-radius
delay bound enables its compact remote history; it is not a general room bound.
