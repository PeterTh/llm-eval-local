# `matmul_claude-opus-5-cc-medium_hybrid_r2`

Date: 2026-10-02

## Scope

Hybrid matrix multiplication, N=8,192. The median is 261 ms, versus 282.357 ms
for Opus r4 and 461.878 ms for the previous Sol 5.6 medium winner.

## Finding

MPI partitions output rows, then CPU AVX kernels and double-precision GPU kernels
compute disjoint portions concurrently. A short untimed tuning trial chooses the
CPU/GPU row split; the timed pass recomputes the full product. A node-shared output
window avoids unnecessary intra-node gathering.

## Close-group comparison

Opus r4 also uses both CPU and GPU arithmetic. It assigns panels dynamically through
atomic work claiming and GPU streams, rather than choosing a fixed split beforehand.
Thus the relevant comparison is two load-balancing strategies, not heterogeneous
execution versus GPU-only execution. The winner's 258–265 ms samples are below
r4's 277.722–283.947 ms, a 7.6% median lead. Both materially improve on the
[older group](matmul_gpt-5.6-sol-medium_hybrid_r5.md).

## Correctness and timing

Retained validation passed. All output rows and the full inner dimension are
computed; CPU and GPU row ownership do not overlap. The corrected interval covers
the synchronized full multiplication, required downloads, node completion and
node-leader collection. The tuning trial is excluded setup, not reused final work.

## Interpretation

A well-balanced CPU/GPU implementation, with a moderate lead over a closely related
dynamic scheduler. The retained measurements do not isolate scheduling overhead
from kernel and partition differences.
