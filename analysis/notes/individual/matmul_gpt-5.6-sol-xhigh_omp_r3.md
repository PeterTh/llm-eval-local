# `matmul_gpt-5.6-sol-xhigh_omp_r3`

Date: 2026-08-25

Status: verified performance explanation; no validation, measurement, or scoring change

## Scope

This note explains the isolated winner in the `matmul` OpenMP cell for data
release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark multiplied 8,832 x 8,832 double-precision matrices on
128 physical cores. Its times are 1,169, 1,151, 1,144, 1,135, and 1,143 ms,
giving a median of 1,144 ms. The next result has a 2,309 ms median, a 2.02x
gap.

## Finding

The advantage comes from packing B into narrow panels and reusing each panel
across several row micro-tiles.

On the evaluated AVX2 CPU, the implementation packs B as 8-column panels. Its
4 x 8 microkernel keeps eight vector accumulators in registers for the complete
dot product. It then groups four such 4-row micro-tiles into a 16-row slab. For
each B panel, all 16 rows are completed before advancing to the next panel.

One packed panel is about 552 KiB, close to the private-cache scale and tiny
compared with the approximately 624 MB full B matrix. The 16-row traversal
therefore consumes each streamed panel for four micro-tiles while it remains
hot in the nearby cache hierarchy.

The runner-up uses an explicit AVX2 microkernel but reads the original
row-major B directly. It completes a small row block across the full matrix,
causing B to be streamed again for successive row blocks. Packing and
cross-micro-tile reuse, rather than merely using intrinsics, separates the
winner.

## Controlled evidence

The retained implementation was rebuilt and reproduced under the benchmark's
128-core placement. It took 1,140-1,166 ms. A temporary variant changed only
the maximum row-cache slab from 16 rows to one 4-row micro-tile. That variant
took 2,260-2,847 ms across repeated runs. The original runner-up reproduced at
2,308-2,343 ms.

Reducing the slab leaves the packed representation and AVX2 microkernel intact
but removes reuse of a B panel across four row micro-tiles. Losing nearly the
entire advantage under that one change identifies panel reuse as the causal
optimization.

## Correctness and timing validity

Packing changes storage order, not matrix values. Each output element still
accumulates K in increasing order, and SIMD is across independent columns and
rows. The row-slab size changes only traversal order among independent output
elements.

The retained validation passed internal validation and external output
comparison. The timer includes B packing and the complete multiplication in
one persistent OpenMP team. The team exits before the timer stops, and all
output rows are covered, including cleanup paths for arbitrary dimensions.

## Interpretation

This is a valid cache-reuse outlier. The 2x result is not explained by
problem-size, timing, or basic AVX2 use; it comes from arranging the loop nest
so an expensive B stream serves four micro-tiles instead of one.

## Non-decisions

- No validation result, benchmark measurement, threshold, or score is changed.
- No generated source is changed.
- The row-slab variants are explanatory evidence, not replacement benchmark
  data.
