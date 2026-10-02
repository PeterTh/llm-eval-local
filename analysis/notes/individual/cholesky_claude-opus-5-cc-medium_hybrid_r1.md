# `cholesky_claude-opus-5-cc-medium_hybrid_r1`

Date: 2026-10-02

## Scope

Hybrid Cholesky, N=4,096. The median is 68 ms, versus 74 ms for Opus r2 and
83.734 ms for Astra 6 r3.

## Finding

Cyclic block columns stay resident on the GPUs. cuSOLVER handles diagonal
factorization and cuBLAS supplies triangular solves and trailing updates.
High-priority lookahead, multiple panel buffers and node-shared panel storage keep
the next diagonal work from waiting for all unrelated trailing work.

## Close-group comparison

Opus r2 also uses cuBLAS for most matrix work, but has a custom 64-wide diagonal
kernel and broadcasts diagonal data through the world communicator. The leading
pair therefore shares library-backed GPU updates, not an identical panel pipeline.
The 68 ms samples are consistently below r2's 72–75 ms, an 8.1% median improvement.
Panel scheduling and data movement offer concrete explanations; the observations
do not separate their contributions.

## Correctness and timing

Retained validation passed. The timed factorization follows panel dependencies,
joins the GPU streams and reaches the final world barrier before reporting.
An unfinished trailing update cannot be hidden by an early local stop.

## Interpretation

A clear but moderate lead within the fast library-backed group, with a more
carefully overlapped panel path rather than a different Cholesky algorithm.
