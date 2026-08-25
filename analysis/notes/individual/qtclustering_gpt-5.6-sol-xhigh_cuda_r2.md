# `qtclustering_gpt-5.6-sol-xhigh_cuda_r2`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the isolated winner in the `qtclustering` CUDA cell for
data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used 7,800 points on one RTX 3090. Its five clustering
times are 800, 804, 799, 810, and 808 ms, giving a median of 804 ms. The
runner-up has a median of 2,160 ms, making this run 2.69x faster.

## Finding

The implementation combines a dense distance matrix with compact
threshold-neighbor lists and keeps the complete outer clustering state on the
GPU.

It precomputes every pair distance once, then builds, for each seed, a list
containing only points initially within the clustering threshold. A CUDA block
evaluates one active seed and stores state only for that compact list. As
members are added, over-threshold candidates are retired permanently. Block
reductions select each next member, while an encoded atomic maximum selects
the globally best seed with the required lower-seed tie break.

Only the winning seed is replayed to materialize members. Cluster marking,
active-seed compaction, best-seed selection, and result accumulation remain on
the device. Host transfers during the loop are limited to the next active
count; compact cluster arrays are copied after clustering.

The runner-up also precomputes a dense distance matrix and updates candidate
diameters incrementally, but it scans all points for each seed. It also
repeatedly transfers active seed lists and winning results between host and
device and maintains more of the outer loop on the host.

## Comparative evidence

The exact deterministic 7,800-point input has an average of 256.8
threshold-neighbors per seed, a maximum of 531, and only 3.29% of all possible
non-self neighbors within the threshold. The winner therefore reduces the hot
candidate state from 7,800 doubles to at most 531 and normally about 257. This
is a roughly 15-30x reduction in state and scan length before later pruning.

At this size the distance matrix is about 464 MiB and the neighbor matrix about
232 MiB. Both comfortably fit on the recorded 24 GiB GPU, so the retained run
takes the intended precomputed-distance, compact-neighbor path. The stable
799-810 ms measurements and the runner-up's exactly repeated 2,160 ms result
are consistent with a structural rather than incidental gap.

A new device-side variant could not be timed in this analysis session because
the GPU driver was unavailable inside the side-session sandbox. The causal
claim therefore rests on the retained device measurements, exact input
neighborhood census, and static execution-path comparison.

## Correctness and timing validity

The neighbor list is lossless: a point farther than the threshold from the
seed can never join a cluster that already contains that seed. Incremental
maximum distances and permanent retirement preserve the original greedy
algorithm. Atomic key encoding preserves maximum cardinality and the
lowest-seed tie break, and replay verifies that the materialized cardinality
matches the evaluated one.

The retained validation passed internal validation and external output
comparison. The host timer wraps the complete clustering routine. Synchronous
device-to-host copies inside and at the end of that routine ensure that all
kernel work is complete before the timer stops; there is no asynchronous
early-stop issue.

## Interpretation

This is a valid GPU algorithm/data-structure outlier. Its advantage comes from
recognizing that the threshold graph is sparse and making that sparsity the
unit of GPU work, while avoiding repeated host/device control traffic.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The neighborhood census is explanatory evidence, not replacement benchmark
  data.
