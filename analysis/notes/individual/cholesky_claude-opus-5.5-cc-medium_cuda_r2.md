# `cholesky_claude-opus-5.5-cc-medium_cuda_r2`

Date: 2026-10-06

## Scope

CUDA Cholesky, N=1,280. All five samples report 3 ms; Opus 5.5 r4 reports 4 ms
and the previous Opus 5 winner reports 6 ms.

## Finding

The small factorization is captured as one CUDA graph, including input movement,
dependent kernels and result downloads. At this size, 32-wide panels use a
single-warp diagonal factorization. A high-priority panel stream advances the next
panel while the main stream updates the remaining trailing matrix, and a third
stream downloads finished rows.

The diagonal kernel reserves otherwise-unused shared memory to discourage sharing
an SM with the trailing update. Panel solves process several rows per warp, and
the update tile height shrinks when the remaining matrix would otherwise expose
too few blocks. These choices target the short serial panel path and launch costs,
not a reduction in the factorization's mathematical work.

## Close-group comparison

The 4 ms r4 uses 64-wide panels, block-level diagonal work and a different
transfer pipeline. The [6 ms Opus 5 winner](cholesky_claude-opus-5-cc-medium_cuda_r1.md)
already uses a 32-wide warp diagonal kernel and overlapping downloads: those
features alone cannot explain the new lead. Graph submission, lookahead and
workspace preparation are the more distinctive changes here.

Unlike the older result, workspace allocation, host pinning, graph construction
and a transfer warmup precede the timer. That matters to this tiny workload even
though no numerical factorization is moved outside the interval. The result is a
prepared-workspace factorization time, not cold-start latency.

## Correctness and timing

Retained validation passed. The graph reads the input matrix, executes the complete
factorization and downloads the result. Both helper streams join the main stream,
which is synchronized before stopping. Graph capture records operations without
executing the factorization; the measured graph launch performs it.

## Interpretation

A credible short-workload improvement with important setup and launch distinctions.
The reported 3-versus-6 ms comparison is coarse: integer-millisecond truncation
does not support a precise twofold throughput claim. No ablation assigns individual
gains to graph launch, panel scheduling or preparation.
