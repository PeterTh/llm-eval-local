# `black-scholes_claude-opus-5-cc-medium_omp_r4`

Date: 2026-10-02

## Scope

OpenMP Black–Scholes, 25 million options. The median is 22.058 ms; Opus r2 and r5
follow at 22.464 and 22.537 ms.

## Finding

A static OpenMP partition evaluates the full pricing formula independently for
each option. Parallel initialization and straightforward contiguous loops support
the compute path; this is not the contract-reuse shortcut of the hybrid winner.

## Close-group comparison

The three Opus implementations share this basic design and have overlapping sample
ranges. The previous
[Terra 5.6 review](black-scholes_gpt-5.6-terra-medium_omp_r1.md), at 23.529 ms,
already describes the same broad full-formula parallel group. The new result is
6.3% below that median but only 1.8% below its nearest peer.

## Correctness and timing

Retained validation passed, all options are evaluated, and the timed parallel loop
completes before reporting. The campaign interleaves memory across NUMA nodes;
parallel initialization therefore does not establish a NUMA-local first-touch
explanation for this ordering.

## Interpretation

A small lead among similar implementations. The measurements do not identify a
unique optimization responsible for r4's position.
