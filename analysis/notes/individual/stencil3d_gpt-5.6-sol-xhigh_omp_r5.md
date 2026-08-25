# `stencil3d_gpt-5.6-sol-xhigh_omp_r5`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains why this run is substantially faster than every other successful
OpenMP result in the `stencil3d` cell. It refers to data release
`local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used a 512 x 512 x 512 grid for 20 iterations on 128 physical
cores. Its five reported computation times are 466, 466, 466, 464, and 466 ms, giving
a median of 466 ms. The next-fastest successful result has a median of 665 ms. This
run therefore takes about 30% less time and delivers about 43% more cell updates per
second than the next result.

## Finding

The advantage is caused by effective spatial cache blocking across the Y and Z
dimensions. The generated implementation divides the interior into 8 x 8 Y/Z tiles
while leaving X contiguous for SIMD execution. It keeps one OpenMP team alive across
all time steps and statically distributes those tiles over the team.

This loop order is important for a 512-cubed double-precision grid. One complete Z
plane occupies 2 MiB, so a conventional traversal that finishes the full Y extent of
one plane before moving to the next cannot retain all adjacent-plane data in a core's
private cache. The tiled traversal advances through several neighboring Z planes for
only a small Y range. The top, center, and bottom bands are consequently reused while
still cache-resident instead of being fetched again after a full-plane traversal.

The other successful implementations inspected in this cell do not perform genuine
Y/Z spatial blocking. Some mention tiling or block contiguous X ranges, but neither
produces the same cross-plane reuse.

## Controlled evidence

The original result was reproduced in an isolated temporary build under the benchmark
resource settings. A conventional implementation from the same model family took
663-669 ms, while this implementation took 468-470 ms.

Changing only the compile-time tile dimensions in temporary copies produced:

| Y tile | Z tile | Computation time |
|---:|---:|---:|
| 8 | 1 | 663 ms |
| 8 | 2 | 534 ms |
| 8 | 4 | 466 ms |
| 8 | 8 | 468 ms |
| 8 | 16 | 471 ms |
| 8 | 32 | 455 ms |
| 4 | 8 | 446 ms |
| 16 | 8 | 479 ms |

The Z-tile-one variant is effectively the conventional traversal and loses the full
advantage. Introducing a modest Z extent recovers it. Because this experiment changes
only tile sizes, it identifies cross-plane cache reuse as the cause rather than model,
compiler, launcher, or run-to-run variation. The slightly better 4 x 8 observation
also shows that the generated 8 x 8 choice is effective but not a uniquely tuned
optimum.

## Correctness and timing validity

The implementation executes every interior cell in all 20 Jacobi iterations. The
implicit barrier after each OpenMP workshare enforces the dependency between time
steps, and leaving the parallel region completes all work before the timer is stopped.
The one-time second-buffer boundary initialization is semantically equivalent to
repeatedly copying those invariant values.

The retained validation run passed internal validation and external output comparison.
A separate full-size comparison against a conventional implementation produced the
same sum, extrema, sample values, and exact 64-bit result hash
`8652bd3ae25b0763`. The timer covers the complete stencil computation and does not
exclude work that another thread continues asynchronously.

## Interpretation

This is a valid algorithmic performance outlier. It does not result from reduced
problem size, skipped iterations, invalid timing, or weaker output checking. The score
should be interpreted as evidence that the generated program found a cache-aware loop
organization that the rest of this OpenMP cell largely missed.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The controlled tile sweep is explanatory evidence, not a replacement benchmark.
