# `cholesky_claude-opus-5-cc-medium_cuda_r1`

Date: 2026-10-02

## Scope

CUDA Cholesky, N=1,280. The median is 6 ms; Opus r2 and Terra 5.6 xhigh r4 both
report 7 ms.

## Finding

The factorization uses 32-wide panels, a warp-level diagonal kernel and tiled
trailing updates with several rows held per thread. A second stream downloads
finished rows while later panels are processed.

## Close-group comparison

Opus r2 also uses 32-wide panels, but a block-level diagonal kernel and larger
trailing tiles with a 4×4 register patch. The
[previous Terra review](cholesky_gpt-5.6-terra-xhigh_cuda_r4.md) places these results
in the same small, launch-sensitive blocked-factorization group. All five samples
for each of the leading results occupy a single whole-millisecond bucket. A one-tick
difference is too coarse to support a precise percentage claim.

## Correctness and timing

Retained validation passed. Allocation, upload, factorization and result downloads
are included, and both streams finish before the timer stops.

## Interpretation

A nominal improvement in a very short benchmark. The kernel and stream differences
are plausible contributors, but this measurement does not resolve their costs.
