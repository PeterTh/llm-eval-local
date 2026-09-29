# `cholesky_claude-opus-5-cc-medium_omp_r3`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `cholesky/omp` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 4992`; calibration and resources were not changed for this batch.

The five retained times are 58.0, 60.0, 58.0, 57.0, 59.0 ms, median **58.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/cholesky_gpt-5.6-sol-xhigh_omp_r2.md), `cholesky_gpt-5.6-sol-xhigh_omp_r2`, had times 80.0, 81.0, 80.0, 80.0, 81.0 ms and median 80.0 ms. The old/new median ratio is 1.3793x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/cholesky_claude-opus-5-cc-medium_omp_r3/cholesky/cholesky.cpp); file SHA-256 `d9890980d1ff6d2ebff0c24083f1a870e883e46e57b16ef2048b9830bf8776c6`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

This is a two-level blocked left-looking factorization. Packed panel rows feed an AVX2 register microkernel, while per-row partial dot products are continued across panels. Cyclic ownership of row blocks remains consistent across phases. The implementation also reestablishes parallel first touch after vector allocation, which matters for a multi-socket matrix working set.

Panel dependencies are enforced by OpenMP worksharing, barriers, and single-thread diagonal steps. The timer wraps the complete factorization, including packed workspaces and the enclosing parallel region; it stops only after the team finishes. Matrix construction is separate.

The 80-to-58 ms change is consistent with improved blocking and locality. The inspected accumulation scheme preserves increasing inner-product order, while retained internal and external validation provide the empirical correctness evidence. No new local-kernel ablation was performed, so attributing the entire gain to any one optimization would be stronger than the evidence.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
