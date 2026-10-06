# `roomsim_claude-opus-5.5-cc-medium_cuda_r3`

Date: 2026-10-06

## Scope

CUDA Roomsim, 5,120 triangles and 10,000 steps. The median is 2,487 ms,
followed by Opus 5.5 r5 at 2,998 ms and r2 at 3,580 ms. The previous leader
measured 4,729 ms.

## Finding

The gain over the nearest competitor comes from propagation, not uniformly faster
phases. The retained phase medians are:

| Phase | Winner r3 | Nearest peer r5 |
| --- | ---: | ---: |
| Precomputation | 426 ms | 420 ms |
| Propagation | 1,668 ms | 2,361 ms |
| Correlation | 397 ms | 215 ms |

Propagation stores row-major coupling weights and compact one-byte delays. Loader
warps stage weights and delayed radiosity into double-buffered shared-memory
tiles; another warp accumulates each receiver in source order. Thus memory
gathering overlaps arithmetic without parallel reassociation of a receiver's sum.

The implementation also reproduces the sequential random stream through MT19937
jump-ahead and GPU generation, with warp-cooperative octree ray traversal.
Correlation exposes both receivers and candidate lags to GPU parallelism while
each correlation sum retains time order. These are full computations, not a
convex-geometry shortcut or an FFT replacement.

## Close-group comparison

R5 also uses GPU random generation, ray packets and ordered tiled propagation,
but transposes coupling coefficients and recomputes delays during simulation.
Its faster correlation does not offset the roughly 693 ms propagation deficit.
The winner's total range, 2,484–2,495 ms, is well below r5's 2,989–3,000 ms:
the 17.0% lead is clearly separated.

The [older Sol winner](roomsim_gpt-5.6-sol-xhigh_cuda_r1.md) spent almost no time
on form factors after exploiting convex geometry, but about 2,410 ms on propagation
and 2,320 ms on correlation. The new result's 47.4% overall improvement is therefore
not explained by omitting precomputation; it spends substantially more there and
recovers much more in the two later phases.

## Correctness and timing

Retained validation passed. All steps and the full lag range execute. Precomputation
and propagation synchronize devices; the final result copy completes correlation
before its host timer stops. The total is the sum of the three completed phase
intervals. The campaign exposes one CUDA device; unused multi-GPU paths do not
explain this result.

## Interpretation

A strong propagation implementation with a directly observed phase-level advantage.
The phase records localize the gain, while the source suggests the memory layout,
stored delays and pipelining as contributors. They do not quantify each separately.
