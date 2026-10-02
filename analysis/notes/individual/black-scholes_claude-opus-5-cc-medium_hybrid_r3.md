# `black-scholes_claude-opus-5-cc-medium_hybrid_r3`

Date: 2026-10-02

## Scope

Hybrid Black–Scholes, 100 million options. The 11.855 ms median led the Claude
release; the pending GPT-6 data adds a 1.213 ms result.

## Finding

The code recognizes the generator's repeated contract structure. A small table of
seven contract families and nine spot/strike ratios replaces most transcendental
pricing arithmetic; an exact ratio check selects the table path, with a full-formula
fallback. Dynamically assigned CPU and GPU chunks still produce every option price.

## Close-group comparison

This is a substantial improvement over the 21.655 ms
[Opus 4.6 result](black-scholes_claude-opus-4.6_hybrid_r5.md), but it is no longer
the fastest retained implementation. The
[new Sol 6 review](black-scholes_gpt-6-sol-medium_hybrid_r5.md)
explains a more direct seven-base-price scaling path and, importantly, a different
output boundary. Opus brings GPU results back to the host inside its timed chunk
processing; Sol's benchmark leaves them on the devices. The roughly tenfold gap
is not a clean comparison of pricing arithmetic alone.

## Correctness and timing

Retained validation passed. Table reuse is grounded in the generated contract
parameters, rather than omitting outputs. The corrected timer includes CPU work,
GPU work and chunk downloads, and reports the maximum rank time after completion.

## Interpretation

An effective input-specialized CPU/GPU implementation. Its place in the ranking
depends both on arithmetic reuse and on whether host-resident output is included.
