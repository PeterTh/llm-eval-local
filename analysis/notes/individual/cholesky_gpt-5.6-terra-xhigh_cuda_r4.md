# `cholesky_gpt-5.6-terra-xhigh_cuda_r4`

Date: 2026-08-25

Status: performance and reporting-resolution explanation; no data change

## Scope

This is the first-place CUDA result in the `cholesky` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The retained benchmark factored a
1,280 x 1,280 matrix. All five parsed times are 7 ms; the next median is 7.821 ms.

## Finding

The factorization is a custom right-looking blocked Cholesky. It uses 64-column panels,
a custom diagonal factorization, a warp-oriented triangular solve, and a lower-triangle
32 x 32 trailing update in which each thread produces four values. Avoiding updates to
the unobserved upper triangle and keeping panels relatively large reduce both work and
launch/library overhead at this small matrix size.

The printed time is lossy. The program converts the floating CUDA elapsed time to an
integer millisecond count before printing. The retained throughput values reconstruct
the five actual times as approximately 7.329, 7.330, 7.336, 7.335, and 7.392 ms, so
the actual median is about 7.335 ms rather than exactly 7 ms.

## Close-group comparison

The 7.821 ms runner-up also uses a blocked right-looking method, but with much smaller
panels and library triangular solve/full-square matrix update operations. These are
different implementations of the same blocked algorithm. On this size, the winner's
lower-only custom update avoids enough work to be about 6.2% faster using reconstructed
times. The apparent 10.5% gap from `7` to `7.821` is an artifact of output rounding.

## Correctness and timing validity

The complete lower-triangular factor is produced, and retained internal validation and
external output comparison passed. CUDA events surround the full factorization and are
synchronized. The issue is reporting precision, not missing work or asynchronous
timing.

## Interpretation

The first place is real, but its margin must be evaluated from the retained throughput
rather than the integer time field. It is a lower-triangle custom-kernel win within the
blocked Cholesky family, not a 7.000 ms measurement.

## Non-decisions

- The parsed benchmark value is not rewritten.
- No generated source, validation status, threshold, or score is changed.
