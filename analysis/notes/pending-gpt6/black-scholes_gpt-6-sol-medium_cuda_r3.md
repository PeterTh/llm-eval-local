# `black-scholes_gpt-6-sol-medium_cuda_r3`

Date: 2026-10-02

## Scope

CUDA Black–Scholes, 25 million options. The median is 1.227 ms, versus
17.942 ms for Sol 6 medium r1 and 19.521 ms for the previously reviewed
[Sol 5.6 xhigh r5](../individual/black-scholes_gpt-5.6-sol-xhigh_cuda_r5.md).

## Finding

The input generator scales the spot and strike of seven base contracts together.
Black–Scholes is homogeneous in those two quantities:
`price(a*S, a*K) = a*price(S, K)` when the other parameters are unchanged.
Each CUDA block prices the seven bases once, then produces every assigned output
by scaling the corresponding base price. The timed work is largely output writes,
not 25 million independent evaluations of logarithms, exponentials and the normal CDF.

The timer ends after device synchronization. The 200 MB result array remains on
the GPU in the benchmark path; validation/result-output modes download it after
the timer. This boundary matters once pricing arithmetic becomes so cheap.

## Close-group comparison

Sol 6 r1 already uses the same mathematical reuse, but always downloads the result
inside its timed interval. The older Sol 5.6 implementation instead evaluates the
full formula for each option and excludes transfers. The two comparisons therefore
do not isolate the same optimization.

A limited [diagnostic](../2026-10-02-black-scholes-diagnostic.json) changed one thing
at a time in this winner. Three measured repetitions gave these medians:

| Variant | Median |
| --- | ---: |
| Unchanged winner | 1.225 ms |
| Full formula for every option; original timer | 34.317 ms |
| Original arithmetic; result download inside timer | 18.667 ms |

The download variant ranged from 18.375 to 26.525 ms. These are diagnostic results,
not replacement benchmark samples. They support both explanations, without assigning
an exact fraction of the cross-implementation gap to either one.

## Correctness and timing

Every option is produced, and the timer waits for the kernel to finish. The identity
specializes the generated input family; it is not a general arbitrary-contract
pricing throughput result. Retained validation passed. Both diagnostic variants
also passed the existing numerical comparison against the unchanged winner at
10,000 options; the full-formula variant was tolerance-equivalent, not bit-identical.

## Interpretation

This is a real reduction in work for this input family, combined with a materially
cheaper output boundary than the nearest competitor. Calling the entire gap a
faster general-purpose pricing kernel would be misleading.
