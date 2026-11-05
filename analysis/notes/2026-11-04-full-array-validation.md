# Complete array validation

The full sweep checked all 6,747 eligible floating-result implementations and
excluded 96 under the existing failed-external-validation category. Of these,
91 had successful performance measurements. Original programs, validation logs
and measurements remain unchanged; the release removes their performance
eligibility rather than rerunning benchmarks.

| Benchmark | Newly failed programs | Finding |
| --- | ---: | --- |
| Roomsim | 94 | 91 exceed the distance tolerance; three fail the existing sum comparison on the supplemental input |
| Nbody | 1 | Three unsampled position components exceed absolute tolerance `1e-5` |
| SpMV | 1 | An uneven four-rank `MPI_Gather` aborts with `MPI_ERR_TRUNCATE` |

The [release impact record](2026-11-05-full-array-validation-impact.json) lists
every ID, its failure reason, prior measurement eligibility, model totals and
joint-score changes. The only changed cell winner is Roomsim hybrid:
`roomsim_gpt-5.6-sol-xhigh_hybrid_r3` fails, and
[Sol 5.6 Medium r2](individual/roomsim_gpt-5.6-sol-medium_hybrid_r2.md) becomes the
winner at 667 ms. Its 2.9% lead over Opus 5.5 is a close-group result, not a new
performance outlier. The other 43 cell winners are unchanged.

## Numerical findings

Most Roomsim failures differ at one or two of 320 receiver distances. For
example, the former hybrid winner returns 25.5 instead of 2 at indices 5 and 6,
a difference of 23.5 against tolerance 5. Different random streams are not
automatically invalid; these exclusions follow numerical discrepancies on the
unchanged reference input, not a prohibition on alternative sampling methods.

Three Roomsim programs pass each individual distance comparison but fail the
existing summary-sum tolerance of 50: `roomsim_claude-sonnet-4.5_hybrid_r1`,
`roomsim_deepseek-v4-flash_omp_r1`, and `roomsim_gpt-5-mini_omp_r2`.
Their sums are 4720, 4709 and 4711.5, respectively, against reference 4772.5.

`nbody_claude-haiku-4.5_hybrid_r3` differs beyond tolerance at indices 2848,
4120 and 4121 out of 6,186 position components. Its maximum absolute error is
approximately `1.062811e-5`, just above the established `1e-5` threshold.

`spmv_gpt-4.1_mpi_r4` splits 1,025 rows as 256, 256, 256 and 257, but uses each
rank's local row count as both send and receive count in `MPI_Gather`.
One unchanged, unwrapped correctness diagnostic confirmed the same truncation
seen under observation. The earlier 128-rank shape check completed successfully;
that does not make the mismatched collective valid. The
[static work-count review](2026-11-04-spmv-work-count.md) had already noted the
uneven-gather concern. This is an execution failure, not an invented numerical
array comparison, and the program already lacked a successful benchmark result.

## Method and coverage

Hardware breakpoints and read-only memory capture observe complete result arrays
in unchanged executables. Each capture must match its own printed name, count
and full-result hash. Elementwise comparison with the unchanged sequential
reference uses absolute tolerance `1e-5`, or 5 for Roomsim distances. The
existing summary comparison also remains in force. Different floating-point
hashes across implementations do not determine correctness.

The sweep uses the approved shape inputs, established base validation resource
allocation and 30-second execution limit. Floyd–Warshall is excluded because
its complete integer result is already covered by a separate check. The
population includes programs whose later benchmark measurements failed.

A stratified 120-program pilot covered the winner, median and 90th-percentile
original validation runtime in each of 40 benchmark/backend strata. It found
four Roomsim failures. A compatibility pilot checked 13 unusual output layouts
and five controls, including a reference. The full sweep reused 133 completed
program checks and added 6,614 observations, plus the single SpMV confirmation
above. These are local CPU/GPU correctness executions, not LLM invocations.

Observer ambiguities were reviewed separately from scientific failures. Saved
captures resolve byte-identical replicas, and source inspection distinguishes
a gathered printed root result from unprinted partial arrays. Nonidentical
Roomsim replicas retain the first printed result used by the unchanged parser;
a passing rank cannot replace a failing primary result.

For `unstructured_gpt-5.6-luna-low_hybrid_r4`, later duplicate output blocks
interleave, but the first block is intact and all four captured arrays exactly
match the reference. It passes under the existing first-block validation rule.
The output concern and reconstruction from original logs and raw rank captures
are retained explicitly. No program was rerun to resolve an output ambiguity,
and the benchmark rule rejecting multiple primary timings is unchanged.

## Retained evidence

The [full export](../../validation-supplements/20261105-full-array-full/export.json)
retains per-ID observations and comparisons, original logs, source and executable
bindings, reviewed exceptions and exact methods. It references the
[published pilot](../../validation-supplements/20261104-full-array-pilot/export.json)
by digest rather than duplicating its records. Complete failure arrays are
deduplicated by SHA-256; successful bulk arrays and executables are omitted.
Small reviewed replica cases retain all captures so the selection can be checked.
The full export occupies 96,302,207 bytes including its receipt; the shared pilot
is retained separately rather than copied again.

The bundled offline verifier checks all 6,747 outcomes and replays complete
failure arrays and the separately confirmed execution failure without invoking
evaluated programs or models:

```sh
ruby validation-supplements/20261105-full-array-full/verification-method/tools/validation_audit/verify_full_array_full_export.rb \
  validation-supplements/20261105-full-array-full
ruby analysis/src/full_array_validation_impact.rb
```

Future native validation includes this full-array step after the ordinary and
supplemental checks. Unsupported observation remains an infrastructure stop for
review, not an automatic program failure. Temporary captures and executable
copies stay on local storage; compact evidence and failure witnesses persist
with the validation records.
