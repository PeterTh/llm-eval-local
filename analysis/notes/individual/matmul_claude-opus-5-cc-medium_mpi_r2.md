# `matmul_claude-opus-5-cc-medium_mpi_r2`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `matmul/mpi` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 6144`; calibration and resources were not changed for this batch.

The five retained times are 161.0, 154.0, 155.0, 158.0, 156.0 ms, median **156.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/matmul_gpt-5.6-sol-xhigh_mpi_r1.md), `matmul_gpt-5.6-sol-xhigh_mpi_r1`, had times 405.0, 399.0, 400.0, 402.0, 390.0 ms and median 400.0 ms. The old/new median ratio is 2.5641x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/matmul_claude-opus-5-cc-medium_mpi_r2/matmul/matmul.cpp); file SHA-256 `e7ce3c5ac7e77eb1c862d41bf6f77df108dd80c17a1d63e9e53a3a5551cf23ea`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

Each rank owns a two-dimensional output block and independently generates the A block-row and B block-column it needs from the exact input formula. Unlike the previous winner's SUMMA pipeline, there is no panel broadcast in the timed multiply. The local kernel is a packed 6-by-8 AVX2/FMA GEMM with MC=144, KC=256, and NC=512; packing and all K panels remain in the interval.

Locally generated inputs do not avoid the multiplication: every owned output element receives all N inner products. Ranks cover disjoint blocks. A barrier precedes computation and an `MPI_MAX` all-reduction supplies the reported duration. Gathering the distributed result is output handling after timing.

Removing timed input communication while retaining an efficient register kernel plausibly explains the 2.56x gain. It is specific to this benchmark's cheaply reproducible inputs, not evidence that arbitrary distributed GEMM can avoid input distribution. No isolated local-kernel ablation establishes an exact causal split.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
