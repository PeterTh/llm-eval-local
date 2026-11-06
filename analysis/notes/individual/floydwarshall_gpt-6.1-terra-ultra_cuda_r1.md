# `floydwarshall_gpt-6.1-terra-ultra_cuda_r1`

## Scope

Static comparison with the previous Floyd–Warshall CUDA winner, using the five
retained measurements at the established benchmark size. No additional runs.

## Finding

This is a small improvement within the established fast implementation family:
32×32 blocked Floyd–Warshall, three ordered kernel phases per pivot, coalesced
column-major accesses, and four register-held output distances per thread in
the dominant non-pivot update. Like the previous winner, it computes distances
without maintaining the unobserved predecessor/path matrix.

## Close-group comparison

The median is **195 ms**, versus **202 ms** for
[Sol 5.6 XHigh r1](floydwarshall_gpt-5.6-sol-xhigh_cuda_r1.md), a 3.5% reduction.
The five samples are 195, 195, 195, 196 and 195 ms; the previous winner's are
203, 202, 201, 200 and 203 ms. These two are ahead of the next result at 245 ms.
The earlier review explains the larger distance-only/tiling advantage over
implementations that retain path tracking.

Ultra uses 32×8-thread blocks for all three phases and pads the allocation to
whole tiles, removing per-element bounds checks from the kernels. Sol uses
32×16 for the pivot/edge phases, 32×8 for the dominant phase at this size, and
explicit bounds checks. These are plausible incremental differences; the
retained measurements do not isolate their individual contributions.

## Correctness and timing

The program passed the applicable scientific and shape/boundary validation.
The pivot and edge kernels avoid rewriting the dependency entries that cannot
change for this nonnegative graph. Device synchronization completes the timed
computation before the host timer stops; allocation, input transfer and result
copy-back are outside that interval, as in the previous winner. No timing
correction was needed.

## Interpretation

A new best individual result, not evidence of a new algorithmic advantage or
uniformly faster Ultra outputs. Omitting the path matrix remains the same
observable-output versus benchmark-spirit distinction documented for the prior
winner; it is not a new validation exception.
