# `cholesky_claude-opus-5.5-cc-medium_hybrid_r1`

Date: 2026-10-06

## Scope

Hybrid Cholesky, N=4,096. The median is 56 ms, followed by Opus 5.5 r2 at 59 ms
and r3 at 61 ms; the previous Opus 5 winner measured 68 ms.

## Finding

Block-cyclic 128-wide columns reside on the GPUs. The owner factors and inverts
the small diagonal block on the CPU, then uses custom GPU matrix kernels for the
panel solve and trailing update. Chunked node-shared panel transfers, lookahead
and concurrent host assembly overlap communication with remaining matrix work.

## Close-group comparison

R2 also uses custom GPU updates, cyclic columns and high-priority lookahead, but
factors panels on the GPU. The
[previous winner](cholesky_claude-opus-5-cc-medium_hybrid_r1.md) instead used
cuSOLVER and cuBLAS. Thus the 17.6% improvement over the old leader describes a new
fast group; the nearest current gap is only 5.1%, with samples at 55–57 versus
58–60 ms. CPU diagonal work is a plausible distinction, not an isolated explanation.

## Correctness and timing

Validation and corrected-source revalidation passed. The factorization completes
dependent panel work, GPU streams and host assembly inside the interval; the
corrected report reduces elapsed time to the maximum rank.

## Interpretation

A modest leader of a new custom-kernel group, with the CPU used for small diagonal
work and GPUs for the large updates.
