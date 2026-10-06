# `black-scholes_claude-opus-5.5-cc-medium_omp_r3`

Date: 2026-10-06

## Scope

OpenMP Black–Scholes, 25 million options. The median is 18.623 ms, versus
22.058 ms for the previous Opus 5 winner and 22.334 ms for Opus 5.5 r2.

## Finding

This is full-formula pricing, not reuse of the seven underlying test contracts.
Every option evaluates the logarithm, square root, normal CDF and discount terms.
The work is statically divided over the OpenMP team, with initialization and a
result-zeroing pass before the timer.

The 18.301–19.409 ms samples are separated from the previous winner's
21.131–22.551 ms. That makes the 15.6% median improvement worth noting even though
the source does not reveal a comparably large algorithmic change.

## Close-group comparison

The [Opus 5 review](black-scholes_claude-opus-5-cc-medium_omp_r4.md) describes almost
the same pricing function, compiled with the same optimization flags. Differences
are principally storage and OpenMP setup: this version uses a default-initializing
option allocator, a standard result vector and explicit `proc_bind(spread)` clauses;
the older version uses raw arrays and conditional manual affinity setup.

Those differences do not establish the cause. The campaign already supplies
128 threads, core places and spread binding, so the old manual-binding branch is
inactive and spread binding is not new. NUMA memory is interleaved in both cases;
the source's first-touch comments are not evidence of local placement. No ablation
separates allocation history, cache state or code-generation effects.

## Correctness and timing

Retained validation passed. The entire pricing loop and its implicit OpenMP
completion barrier are timed; initialization remains outside, as in the reference.
There is no source-visible skipped pricing work.

## Interpretation

A consistently faster retained measurement within the full-formula family, but
not an identified new algorithm. The observed lead should not be attributed to
NUMA placement or a unique affinity optimization.
