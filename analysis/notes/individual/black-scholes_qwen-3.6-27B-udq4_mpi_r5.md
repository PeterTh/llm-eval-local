# `black-scholes_qwen-3.6-27B-udq4_mpi_r5`

Date: 2026-08-25

Status: timing-corrected result reviewed; no further data change

## Scope

This is the first-place MPI result in the `black-scholes` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark priced 10,000,000
options on 128 ranks. The corrected five times are 8.218, 8.164, 7.818, 7.651, and
7.624 ms, giving a 7.818 ms median. The next median is 7.846 ms.

## Finding

There is no distinctive computation responsible for first place. Rank zero generates
the options, contiguous option ranges are distributed with `MPI_Scatterv`, every rank
executes the same scalar Black--Scholes loop, and results are collected with
`MPI_Gatherv`. Several leading implementations have effectively this same AoS,
scalar, contiguous-range solution shape.

## Close-group comparison

The 0.028 ms gap to second place is 0.36%, far below the variation within either
five-run sample. Other leading medians around 7.9 ms also use the same distribution
and scalar formula. Minor differences in allocation, collective setup, or compiler
code generation do not support a causal first-place claim. This cell should be treated
as a tied fast group.

## Correctness and timing validity

The original generated program was one of the programs identified with rank-local
timing. Its retained timing-corrected version changes only measurement: ranks begin
from a barrier, each measures the complete distributed calculation, and rank zero
reports an `MPI_MAX` reduction. The corrected source is the version represented by
these benchmark values, and the timing-fix metadata preserves that fact.

The correction does not alter option distribution, pricing, result collection, or
output. Retained internal validation and external output comparison passed.

## Interpretation

First place is a noise-level ordering among equivalent implementations. The result is
valid after the recorded timing-only correction, but it is not evidence of a novel MPI
or numerical optimization.

## Non-decisions

- No additional source correction is proposed.
- No measurement, threshold, or score is changed.
