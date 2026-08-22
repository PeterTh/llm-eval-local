# Sol xhigh MPI SIMD classification boundary

Date: 2026-08-22  
Status: verified analysis note; no scoring or methodology change

## Scope

This note investigates why GPT-5.6 Sol xhigh has 11 invalid results (scores 0-4)
while GPT-5.6 Sol medium has 6 in the expanded local evaluation. It uses release
`local-eval-2026-08-22` at commit `bfb6df4`, especially
[`scored_results.csv`](../../data/scoring/scored_results.csv), the retained validation
records, the frozen pipeline snapshot, and generated-program commit
[`e8d10c43`](https://github.com/PeterTh/llm-eval-generated/tree/e8d10c43d7fcdca42862537b0eb7d0d5fab6da66).

## Result decomposition

| First failed stage | Score | Sol medium | Sol xhigh | Difference |
|---|---:|---:|---:|---:|
| Parallelization-target match | 0 | 0 | 6 | +6 |
| Validation execution | 2 | 0 | 1 | +1 |
| Output comparison | 4 | 6 | 4 | -2 |
| **All invalid results** | **0-4** | **6/220 (2.73%)** | **11/220 (5.00%)** | **+5** |

The entire net increase is therefore explained by six additional target-matching
rejections and one execution failure, partly offset by Sol xhigh having two fewer
output-comparison failures.

## Verified MPI/SIMD evidence

All six Sol xhigh score-0 results requested MPI and were rejected because the detector
returned `["omp", "mpi"]`:

- `cholesky_gpt-5.6-sol-xhigh_mpi_r1`
- `cholesky_gpt-5.6-sol-xhigh_mpi_r3`
- `cholesky_gpt-5.6-sol-xhigh_mpi_r4`
- `floydwarshall_gpt-5.6-sol-xhigh_mpi_r4`
- `matmul_gpt-5.6-sol-xhigh_mpi_r4`
- `nbody_gpt-5.6-sol-xhigh_mpi_r3`

Inspection of the immutable generated sources found 21 OpenMP directives across these
six programs. Every one is `#pragma omp simd`, optionally with a SIMD reduction; none
is an OpenMP `parallel`, `parallel for`, `for`, `task`, or teams directive. The CMake
files use `-fopenmp-simd` and do not link an OpenMP runtime. Several generated comments
also explicitly describe the SIMD directives as preserving an MPI-only execution
model. Representative source evidence:

- [Cholesky SIMD-only compiler configuration](https://github.com/PeterTh/llm-eval-generated/blob/e8d10c43d7fcdca42862537b0eb7d0d5fab6da66/20260805-120633/cholesky_gpt-5.6-sol-xhigh_mpi_r1/cholesky/CMakeLists.txt#L12-L18)
- [Cholesky `omp simd` reduction](https://github.com/PeterTh/llm-eval-generated/blob/e8d10c43d7fcdca42862537b0eb7d0d5fab6da66/20260805-120633/cholesky_gpt-5.6-sol-xhigh_mpi_r1/cholesky/cholesky.cpp#L155-L163)
- [N-body SIMD-only compiler configuration](https://github.com/PeterTh/llm-eval-generated/blob/e8d10c43d7fcdca42862537b0eb7d0d5fab6da66/20260805-120633/nbody_gpt-5.6-sol-xhigh_mpi_r3/nbody/CMakeLists.txt#L12-L23)
- [N-body `omp simd` loop](https://github.com/PeterTh/llm-eval-generated/blob/e8d10c43d7fcdca42862537b0eb7d0d5fab6da66/20260805-120633/nbody_gpt-5.6-sol-xhigh_mpi_r3/nbody/nbody.cpp#L112-L123)

This is not a faulty result join or an inaccurate record. The frozen evaluator defines
OpenMP detection as the literal presence of `#pragma omp` in the benchmark source
([`validation_helper.rb`](../../method/pipeline/validation_helper.rb)), then requires
the detected set for a non-hybrid target to equal the requested target exactly
([`validation_pipeline.rb`](../../method/pipeline/lib/local_evaluation/validation_pipeline.rb)).
The six score-0 assignments therefore follow the declared and published rule.

The same boundary occurs in three Sol low MPI results, each also containing only
`omp simd`:

- `cholesky_gpt-5.6-sol-low_mpi_r4`
- `matmul_gpt-5.6-sol-low_mpi_r3`
- `stencil3d_gpt-5.6-sol-low_mpi_r3`

Sol medium has no MPI result containing an OpenMP pragma. The only other corpus result
with the same `["omp", "mpi"]` rejection is
`cahn-hilliard_claude-haiku-4.5_mpi_r3`; unlike the Sol cases, it contains three genuine
`omp parallel for collapse(3)` directives and is runtime hybrid parallelization.

## Independent Sol xhigh failure

`stencil3d_gpt-5.6-sol-xhigh_hybrid_r2` is a separate, genuine score-2 failure. It
configured and built successfully, but aborted during validation. The launcher exposed
one assigned GPU to each of four local MPI ranks; the program incorrectly required each
rank to see four visible devices and called `MPI_Abort` with exit code 2. The exact
stderr is retained in the corresponding record in
[`stencil3d/hybrid.jsonl`](../../data/validation/records/stencil3d/hybrid.jsonl).

The remaining four Sol xhigh invalid results are output-comparison failures: three
RoomSim results and one SpMV result. Sol medium has six output-comparison failures:
four RoomSim, one SpMV, and one QT clustering result.

## Statistical context

The overall invalid-rate comparison, 11/220 versus 6/220, gives a two-sided Fisher
exact `p = 0.323`. Considered only as an exploratory mechanism check, the score-0
comparison is 6/220 versus 0/220 (`p = 0.030`), or 6/55 versus 0/55 within MPI
(`p = 0.027`). These values are uncorrected and were computed after observing the
pattern; they are descriptive evidence, not a pre-registered significance claim.

## Interpretation

The larger invalid segment for Sol xhigh should not be summarized simply as a marked
increase in broken programs. Its distinguishing behavior is more aggressive explicit
SIMD vectorization inside otherwise MPI-only implementations. The current taxonomy
counts that as an additional OpenMP parallelization approach even though it creates no
OpenMP thread team and adds no OpenMP runtime dependency.

This is a real and interesting boundary between two defensible meanings of an
"OpenMP program": use of any OpenMP directive versus use of OpenMP as the requested
shared-memory execution model. The primary dataset consistently applies the first
meaning.

## Deferred analysis

1. Define a sensitivity classification that distinguishes OpenMP threading/worksharing
   directives from SIMD-only directives.
2. Revalidate the nine affected Sol MPI results under that alternative first-stage
   rule. They cannot be assigned counterfactual scores from existing data because the
   primary pipeline stopped before build, execution, comparison, and benchmarking.
3. Report the frozen primary analysis and the sensitivity analysis side by side rather
   than silently replacing the primary scores.
4. Audit CUDA-target mismatches involving both OpenMP and CUDA for the same SIMD-only
   boundary before generalizing any revised detector.
5. Consider describing explicit SIMD use as an orthogonal optimization attribute in
   the expanded paper rather than folding it into the execution-model label.

## Non-decisions

- No score or validation record is changed by this note.
- No detector or pipeline behavior is changed by this note.
- The six Sol xhigh MPI programs are not assumed valid; later stages were never run.
- The note does not claim that Sol xhigh has a statistically established higher general
  failure rate than Sol medium.
- No paper wording or figure is changed yet.
