# `floydwarshall_claude-opus-5-cc-medium_hybrid_r5`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `floydwarshall/hybrid` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 10240`; calibration and resources were not changed for this batch.

The five retained times are 146.0, 146.0, 146.0, 146.0, 145.0 ms, median **146.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/floydwarshall_gpt-5.6-sol-xhigh_hybrid_r1.md), `floydwarshall_gpt-5.6-sol-xhigh_hybrid_r1`, had times 467.0, 455.0, 450.0, 490.0, 466.0 ms and median 466.0 ms. The old/new median ratio is 3.1918x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/4500d708ad5c7b5d1594f93704011d6dfbca09a1/20260901-162328/floydwarshall_claude-opus-5-cc-medium_hybrid_r5/floydwarshall/floydwarshall.cpp); file SHA-256 `6a45cbb2ade409d0ac3c1231c00b6c80e1767c680da7b87a7bfd9612c1adc615`. Timing-fixed flag: **true**. The accepted timing-only correction and scoped revalidation remain part of the record; the original is available at commit `db27e2872a28b900024d318f6a3004a3a7fddfa7`.

## Implementation and timing

A three-phase blocked Floyd–Warshall uses 64-by-64 tiles, with each CUDA thread holding multiple distances in registers. MPI partitions block rows. The next pivot panel is prepared early, allowing its host/device exchange to overlap the remaining phase-three work; shared-memory windows distribute panels inside the node. OpenMP is used for host generation and result handling.

The corrected timer covers the input distance upload, every pivot phase and exchange, result downloads, both stream synchronizations, and a final world barrier. Per-rank millisecond durations are then reduced with `MPI_MAX`. The retained value is therefore not an unsynchronized kernel-launch or rank-local time.

The 3.19x improvement has a plausible blocked-kernel and communication-overlap explanation. Phase dependencies are explicit and the retained comparison passed. This review does not prove behavior for arbitrary weighted graphs or independently validate every path-matrix tie choice; the release uses the established benchmark's validation contract. No new ablation or replacement measurement was used.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
