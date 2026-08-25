# `black-scholes_gpt-5.6-sol-xhigh_cuda_r5`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This note covers the first-place CUDA result in the `black-scholes` cell of data
release `local-eval-2026-08-25` at data commit `f83773e`. The retained benchmark
priced 25,000,000 options. Its five computation times are 20.114, 19.717, 19.521,
19.519, and 19.516 ms, with a 19.521 ms median. The next median is 20.899 ms.

## Finding

The implementation avoids materializing the repeated input option arrays on the
device. The benchmark generates options from seven fixed base cases, and this kernel
reconstructs the appropriate case from the option index while writing only the price
array. Its grid organization groups work by base case, so neighboring threads share
the call/put branch and constants. It therefore performs fewer global loads and has
less branch divergence than a conventional one-thread-per-option kernel over an AoS
or SoA input array.

The numerical work is otherwise the same Black--Scholes formula, including the same
logarithm, exponential, square root, and error-function evaluations.

## Close-group comparison

The closest implementations use the conventional shape: one CUDA thread reads one
fully stored option and computes one price. They differ mainly between structure-of-
arrays and array-of-structures storage. This winner therefore has a genuinely
different data-generation and branch-coherence strategy, not merely a different
block size.

The median advantage is about 6.6%, but the distributions overlap: the runner-up has
two individual measurements below 19 ms. The solution-shape advantage is credible;
the exact ordering and size of the median gap should not be read as a stable 6.6%
hardware effect.

## Correctness and timing validity

Each logical option is still evaluated once, and reconstructing the seven deterministic
base cases is equivalent to reading the generated arrays. Retained internal validation
and external output comparison passed. CUDA timing brackets the complete pricing
kernel and synchronizes through events; allocation, input generation, and transfers
are outside the computation interval for the compared implementations.

## Interpretation

This is a valid, modest kernel/data-layout win. It is also part of a noisy fast group,
so the important result is the distinct low-traffic solution shape rather than the
precise first-place margin.

## Non-decisions

- No generated source or retained result is changed.
- No threshold or score is changed.
