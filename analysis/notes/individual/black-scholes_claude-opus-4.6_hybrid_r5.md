# `black-scholes_claude-opus-4.6_hybrid_r5`

Date: 2026-08-25

Status: verified corrected-timing result and performance explanation; no further data change

## Scope

This note explains the first-place outlier in the `black-scholes` hybrid cell
for data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark priced 100,000,000 options on four MPI ranks, with one
RTX 3090 and 32 OpenMP cores per rank. Its corrected times are 21.653, 21.680,
21.655, 21.661, and 21.646 ms, giving a median of 21.655 ms. The next result
has a 30.935 ms median, so the scored kernel is 1.43x faster.

## Finding

The kernel's advantage is predominantly its structure-of-arrays input layout,
with a secondary benefit from assigning one CUDA thread to each option.

The implementation places type, strike, spot, dividend yield, interest rate,
maturity, and volatility in seven separate device arrays. Consecutive threads
therefore load consecutive values for every field. It launches enough blocks
to give every local option one logical thread, with no grid-stride loop.

The runner-up passes an array of 56-byte option records. For any one field,
neighboring CUDA threads access addresses 56 bytes apart; cache reuse can
recover some of the fetched records, but the individual field instructions
require many more memory transactions than the winner's contiguous arrays.
The runner-up also caps its launch at 32 blocks per streaming multiprocessor
and processes the approximately 25 million local options with a grid-stride
loop.

The mathematical work is otherwise very similar: double-precision square
root, logarithm, exponentials, and error-function evaluations followed by the
same call/put formula.

## Comparative evidence

Static compilation for the recorded GPU architecture reports 40 registers,
zero spills, and no barriers for both kernels. The gap is therefore not caused
by one implementation accidentally spilling its transcendental-heavy state.
It is consistent with input coalescing and launch organization.

The retained 21.646-21.680 ms range is exceptionally stable. The winner also
does not pre-warm its kernel outside the timer, whereas the runner-up performs
a one-thread warm-up. Any first-launch overhead therefore makes the comparison
conservative rather than explaining the win.

A live layout ablation could not be timed in this side-session sandbox because
the GPU driver was unavailable. The causal conclusion is based on the retained
kernel measurements, matched compiler resource counts, and the direct
memory-layout comparison.

## Correctness and corrected timing

The structure-of-arrays conversion preserves all six numerical inputs and the
option type. Validation-only expected values and tolerances are not needed by
the device kernel. The retained validation passed internal validation and
external output comparison.

The originally generated source had a rank-local timing defect and did not
aggregate the distributed duration. That version was identified by the timing
audit, corrected only in its timing code, independently reviewed, and rerun.
The retained 21.655 ms median is from the corrected source.

The corrected timer begins after an MPI barrier, launches the complete local
kernel, synchronizes the device, executes a trailing barrier, and reduces the
per-rank microsecond durations with `MPI_MAX`. It therefore reports the
slowest-rank makespan. The corrected source and rerun provenance explicitly
retain the timing-fix flag.

The score is a computation-kernel score, not end-to-end throughput. The
retained wall time is about 13.8 s because generation, conversion, transfers,
and result handling are outside the measured kernel. The runner-up has a
shorter total wall time despite its slower scored kernel.

## Interpretation

The final retained score is valid after the documented timing correction. Its
1.43x lead is best understood as a coalesced SoA GPU-kernel advantage, with the
important caveat that it is not the fastest end-to-end program.

## Non-decisions

- The already-applied timing correction and scoped rerun are not changed.
- No validation result, retained measurement, threshold, or score is changed.
- No generated source is changed by this analysis.
