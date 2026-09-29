# `cholesky_claude-opus-5-cc-medium_mpi_r4`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `cholesky/mpi` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-n 3072`; calibration and resources were not changed for this batch.

The five retained times are 31.0, 31.0, 31.0, 31.0, 31.0 ms, median **31.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/cholesky_gpt-5.6-sol-xhigh_mpi_r5.md), `cholesky_gpt-5.6-sol-xhigh_mpi_r5`, had times 48.636, 56.582, 55.919, 57.762, 53.449 ms and median 55.919 ms. The old/new median ratio is 1.8038x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/cholesky_claude-opus-5-cc-medium_mpi_r4/cholesky/cholesky.cpp); file SHA-256 `17dd3560ee580fac3bd8c5b2361cd1d015e1022549fbb0f45d968eb35bd5079b`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

The implementation uses a two-dimensional block-cyclic matrix distribution and an explicit packed 8-by-6 AVX2/FMA update kernel. The next panel is updated and factored before bulk trailing updates; nonblocking row broadcasts and a panel-transpose all-gather overlap useful computation. The distributed factorization performs the full panel sequence, not a local diagonal-only approximation.

Random input storage is shared per node, but each rank generates its own owned matrix entries before the timer. The timed factorization includes packing, panel communication, lookahead, and trailing updates. A world barrier follows completion before root timestamps the end, so root's duration is a synchronized distributed interval. Result gathering and validation follow it.

A 31 ms median is plausible for a well-blocked, communication-overlapped factorization at N=3072, but integer-millisecond output limits fine-grained comparisons. This static explanation does not isolate SIMD throughput from the communication schedule. No new source or timing correction is proposed by this review.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
