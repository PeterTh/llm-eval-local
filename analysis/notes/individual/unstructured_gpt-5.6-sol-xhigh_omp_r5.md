# `unstructured_gpt-5.6-sol-xhigh_omp_r5`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the first-place outlier in the `unstructured` OpenMP cell
for data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used a 5,000 x 5,000 generated mesh for 134 iterations
on 128 physical cores. Its times are 1,068, 1,065, 1,062, 1,066, and 1,069 ms,
giving a median of 1,066 ms. The next result has a 2,231 ms median, so this run
is 2.09x faster.

## Finding

The dominant optimization is removal of an invariant per-edge value from a
bandwidth-bound Jacobi loop.

Every generated connection has flux coefficient 1.0. This implementation
therefore stores only four 32-bit neighbor indices plus one-byte material and
connection counts. Its static element record occupies 20 bytes. The runner-up
stores four additional double-precision flux coefficients and wider metadata,
making its record 56 bytes.

At 25 million elements, the static connectivity array is consequently about
500 MB instead of 1.4 GB. The two dynamic buffers add 800 MB in either case.
The winner saves about 900 MB and, more importantly, avoids rereading those
invariant doubles in every one of the 134 iterations.

The implementation also keeps one OpenMP team alive, assigns each worker one
contiguous range once, and uses the single Jacobi barrier required between
iterations. The runner-up has a similar persistent-team structure, so this is
secondary to the record compaction.

## Controlled evidence

A temporary variant changed only the winner's static record and hot expression:
it restored four double flux values, initialized each to 1.0, and multiplied by
the stored value. The compact original took 1,075 and 1,080 ms. The expanded
variant took 2,244 and 2,249 ms.

Both variants produced the exact same full-size result hash,
`75A5E0494C1A64C0`. The 2.08x controlled ratio essentially reproduces the
retained 2.09x first/second ratio and isolates memory traffic as the cause.

## Correctness and timing validity

Replacing multiplication by a stored constant 1.0 with the same expression
without that multiplication is exact for the generated mesh. Connection order,
iteration count, arithmetic order of the four neighbor contributions, double
buffering, and the per-iteration barrier remain unchanged.

The retained validation passed internal validation and external comparison
with an exact result hash. The timer surrounds all 134 iterations and stops
only after the persistent OpenMP region has completed. The implementation does
not omit an iteration or leave worker threads running beyond the timer.

The throughput display uses `n_iters - 1` in its derived rate, but the
reported computation time—the value used for scoring—covers all 134 executed
iterations. That display-only formula does not explain or affect the score.

## Interpretation

This is a valid memory-layout outlier. The generated connectivity is nominally
unstructured, but one of its fields is invariant. Removing that field cuts the
dominant read stream enough to double throughput on this memory-bound workload.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The temporary expanded-record run is explanatory evidence, not replacement
  benchmark data.
