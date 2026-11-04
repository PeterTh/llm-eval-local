# Full array validation pilot

The pilot found four Roomsim implementations whose printed summaries pass the
existing comparison, but whose complete distance arrays exceed its distance
tolerance of 5. The other 116 stratified checks passed. The approved full sweep
covers 6,747 programs and is in progress; these findings are not yet incorporated
into the scored release.

| Implementation | Failing indices | Reference versus observed | Largest difference |
| --- | --- | --- | ---: |
| `roomsim_gpt-5.6-sol-xhigh_hybrid_r3` | 5, 6 | 2 versus 25.5 | 23.5 |
| `roomsim_gpt-5.6-terra-low_hybrid_r4` | 103 | 3.5 versus 25.5 | 22 |
| `roomsim_gpt-5.6-terra-low_mpi_r5` | 6 | 2 versus 25.5 | 23.5 |
| `roomsim_qwen3.7-plus_omp_r5` | 100 | 3 versus 25.5 | 22.5 |

Indices are zero-based. All use `-v -o -n 320 -t 101 -s 7 -r 0.7`.
The first implementation is the current hybrid winner. The earlier
[winner audit](2026-11-03-winner-validity-audit.md) noted its changed random stream;
the new finding is a numerical discrepancy, not a blanket prohibition on alternate
sampling methods. The comparison does not establish which implementation change
caused each discrepancy.

## Method and coverage

Hardware breakpoints and read-only memory capture observe the existing result
arrays in unchanged executables. A captured array must match its own printed
name, count and full-result hash. Elementwise comparison against the unchanged
sequential reference uses absolute tolerance `1e-5`, or 5 for Roomsim distances.
Different floating-point hashes alone do not determine correctness.

The stratified pilot selected the current winner, median and 90th-percentile
original validation runtime in each of 40 benchmark/backend strata. It uses the
approved shape inputs, established validation allocations and 30-second limit.
Floyd–Warshall is excluded because its full integer result was already checked.
Neither generated sources nor input programs changed, and no performance
benchmark was rerun.

Static symbol checks covered all 6,747 candidates. Thirteen needed reviewed
observers for custom allocators, spans, inlined result routines, a raw-pointer
printer or streamed rank slabs. All thirteen and five controls passed a separate
compatibility pilot. Streamed stencil output combines captured slabs with the
fixed faces emitted by that program; the assembled bytes must match its own
printed full-result hash.

Three duplicate-rank capture ambiguities were resolved from saved, byte-identical
arrays without rerunning programs. The benchmark rule for multiple primary
timings remains unchanged. Observer failures remain separate from numerical
failures.

## Retained evidence

The [pilot export](../../validation-supplements/20261104-full-array-pilot/export.json)
contains observations, comparisons, exact method versions, source and executable
bindings, and all scalar bytes needed to independently reproduce the four
numerical failures. It retains 6,957,819 bytes excluding its receipt, without
executables or bulk arrays from successful checks. Original prototype errors
remain available separately from successful observations.

The full sweep reuses 133 completed program checks and needs 6,614 new correctness
executions. Its projection is 6.3 hours, or 9.6 hours conservatively. These are
local CPU/GPU executions, not LLM invocations. New failures will use the existing
failed external validation category; original measurements remain preserved.
