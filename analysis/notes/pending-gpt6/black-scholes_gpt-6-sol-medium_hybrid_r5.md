# `black-scholes_gpt-6-sol-medium_hybrid_r5`

Date: 2026-10-02

## Scope

Hybrid Black–Scholes, 100 million options on four ranks and four GPUs. The median
is 1.213 ms, versus 11.855 ms for
[Opus 5 r3](../individual/black-scholes_claude-opus-5-cc-medium_hybrid_r3.md).

## Finding

The generator supplies seven contracts with their spot and strike scaled together.
The code exploits `price(a*S, a*K) = a*price(S, K)`: the CPU computes seven base
prices before timing, and each GPU writes its local outputs by multiplying those
prices by the generated scale factors. All 100 million outputs are produced, but
almost none of the timed work is full Black–Scholes arithmetic.

There are 25 million outputs per GPU, matching the single-GPU CUDA problem size.
The roughly 1.2 ms CUDA and hybrid results are consequently plausible together;
this is not a fourfold increase in the work performed by each device. OpenMP mainly
participates in host-side orchestration, rather than adding a substantial CPU
pricing contribution.

## Close-group comparison

Opus 5 also reuses pricing arithmetic, through a small ratio table and a fallback
formula, but combines CPU and GPU chunks and copies GPU results to the host inside
the measured interval. Sol instead leaves results on the devices unless validation
or result output is requested. The comparison mixes specialization, scheduling and
the result-transfer boundary.

The [related CUDA review](black-scholes_gpt-6-sol-medium_cuda_r3.md) includes a
controlled diagnostic: adding the download alone changed its median from 1.225 to
18.667 ms. That supports the importance of the boundary; it is not a measurement
of the hybrid implementation or a prediction of its four-GPU transfer time.

## Correctness and timing

Retained validation passed. A barrier precedes the timed GPU work, device
synchronization precedes each local stop, and `MPI_MAX` reports the slowest rank.
This is not a rank-local undermeasurement. Base-price setup is outside the timer;
downloads occur inside it only in validation/result-output modes.

## Interpretation

The outlier reflects very cheap, input-specialized device output generation. Its
lead should not be interpreted as a comparable speedup for arbitrary contracts or
for an application requiring all prices back in host memory.
