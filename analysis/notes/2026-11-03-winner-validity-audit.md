# Current-winner validity and workload audit

## Finding

This note records the audit before the [supplemental validation changes](2026-11-04-validation-strengthening.md).
The focused audit covered all **44 benchmark/backend winners** in release
`c75207d5608801d820eceffe4ffeae6576e4be51`. It found **no newly demonstrated
invalid winner**. All **59 completed winner diagnostics passed** the unchanged
internal checks and external numerical comparator.

It did demonstrate weaknesses in what the validation can establish:

- A wrong Floyd–Warshall distance can escape both validators.
- Wrong stencil interior values can preserve every numerically compared output.
- SpMV's final vector cannot establish how many requested repetitions ran.
- Small validation inputs omit some measured-size fast paths and the 128-rank
  MPI topology.

The first two statements are backed by deliberately corrupted **reference**
results, not by failing winner results. Passing the additional cases is useful
evidence, not proof that the winners are correct for all inputs. No generated
source, validation policy, eligibility, benchmark measurement or website changed
during this focused audit.

Separately, several winning implementations specialize the input family or
omit unobserved work. These merit interpretation notes; they are not automatically
invalid under the existing rules.

## Scope and evidence

The review followed input construction, computation/iteration count, partition
and boundary handling, validation branches, result production, timing completion,
and size-dependent paths. Existing individual reviews provided context; this was
not a formal proof or a line-by-line independent reimplementation.

The [evidence](2026-11-03-winner-validity/evidence.json) retains every winner ID,
effective Git revision (including timing corrections), source-file digest,
existing review link, focused audit observation, exact diagnostic arguments,
verified build binding, and comparison output. It also retains unsuccessful
diagnostic launches separately from scientific checks.

All 44 winners' `common/results_output.hpp` and `common/hash.hpp` match the
frozen input helpers byte-for-byte. No changed output formatter was found.
Result hashes remain **informational**, as in the established validation.
The numerical counterexamples below do not treat hash differences as failures.

Sources came from the generated-output repository; the sequential reference is
input commit `2bc11aeac658a87b5cae25d03e0669f65d32922e`. The native driver is
experiment commit `f64915ac0ae289ee9333c4c52e98c9af2f6dfd54`, with relevant
method files individually hashed in the evidence. All 55 winner/reference builds
were reused only after exact source-tree and successful-build-receipt checks.
Builds and execution were local under `/tmp`; no binaries or repeated source
trees are retained here.

## Confirmed validation blind spots

### 1. Sparse numerical output, especially Floyd–Warshall and stencil

The external comparator checks element count and the printed numerical fields,
normally with absolute tolerance `1e-5`. Floating-point output consists of
sum, min, max and five fixed samples; integer output has min, max and five
samples, **but no sum**. It does not compare the complete numerical arrays.

Two small counterexamples include the frozen sequential implementation without
editing it, compute its correct result, then deliberately alter that result
before invoking its original validation and result-printing functions:

| Case | Deliberate numerical error | Existing checks |
| --- | --- | --- |
| Floyd–Warshall, `n=512` | Distance at row 11, column 12 changes from 4 to 1. | Internal validation and external comparison both pass. |
| Stencil, `64³`, 20 iterations | Swap interior cells (1,1,1) and (2,1,1): 11.4065739046 and 10.8412928852. Two cells are wrong by about 0.565281. | Internal validation and external comparison both pass. |

For Floyd–Warshall, the original internal test checks the diagonal and triangle
inequalities for a restricted set of rows/columns; this entry is outside that
coverage. For stencil, swapping the values preserves sum/min/max, and all five
fixed samples on the standard cubic grid lie on fixed boundaries. The usual
bounds/finite-value internal test also accepts the swap. These demonstrate
**actual missed numerical errors**, not merely different hashes.

Other benchmarks have related limits, without an additional demonstrated
counterexample here: Matmul's internal direct-product check samples the top-left
5×5 region; Cahn–Hilliard and Nbody primarily check numerical sanity; QT's
diameter/duplicate checks do not independently establish greedy-choice
equivalence; Roomsim checks coarse final distance statistics rather than the
full form-factor/radiosity computation. Nbody's printed energy is diagnostic,
not a conservation requirement.

Cholesky's reconstruction and SpMV's full-vector internal checks are stronger.
They are still generated-program code rather than a fully independent external
oracle. In particular, Cholesky CUDA uses related multiplication machinery in
input construction and reconstruction. No common-mode arithmetic error was
demonstrated.

### 2. Repetition count is not observable from SpMV's result

The frozen sequential SpMV program produces an identical result block,
**including its hash**, with one versus eleven repetitions at
`-n 1025 -s 40`. It repeatedly computes the same immutable `A × x`; it does
not feed each output back into the next input.

All four current winners retain explicit requested-repetition loops: a
persistent CUDA loop, batched CUDA graphs plus a remainder, an MPI local
iteration loop, and an OpenMP persistent team. **No iteration omission was
identified.** Nevertheless, comparing the final vector—even every element—cannot
detect that class of omission. This needs source/work-count evidence, not just
a stronger output checksum.

### 3. Input, topology and fast-path coverage

Standard validation uses one mostly aligned shape and commonly an even step
count. It uses four MPI ranks rather than the measured 128, and fewer OpenMP
threads. The additional cases deliberately include nonmultiples of common tile
sizes, odd iteration counts, noncubic grids and a different QT threshold.

| Benchmark | Additional case, with the usual validation/result flags |
| --- | --- |
| Black–Scholes | `-n 10003` |
| Cahn–Hilliard | `-x 65 -y 61 -z 67 -i 21` |
| Cholesky / Floyd–Warshall / Matmul | `-n 513` |
| Nbody | `-n 1031 -s 11` |
| QT clustering | `-n 1001 -t 1.3` |
| Roomsim | `-n 320 -t 101 -s 7 -r 0.7`, with `-v -o` |
| SpMV | `-n 1025 -s 40 -i 11` |
| Stencil | `-x 65 -y 61 -z 67 -i 21` |
| Unstructured | `-n 33 -i 513` |

All 44 winners passed. Every MPI winner also passed the same case at 128 ranks.
Four more checks specifically exercised paths absent from the standard inputs:

| Winner | Path and diagnostic | Outcome |
| --- | --- | --- |
| Cahn–Hilliard Opus 5 OMP r4 | Cache/size-selected fused path, `-x 512 -i 3`, 128 threads. | Pass |
| Stencil Opus 5 OMP r1 | Large-grid non-temporal-store path, `-x 512 -i 3`, 128 threads. | Pass |
| Cholesky Opus 5.5 OMP r1 | 96-wide tile above the `n=1536` threshold, `-n 1537`, 128 threads. | Pass |
| SpMV Sol 6.1 xhigh hybrid r4 | 64-iteration graph plus three tail launches, `-n 1024 -s 10 -i 67`, four ranks × 32 threads. | Pass |

These give 59 winner checks and 15 sequential reference checks. Each execution
had a 30-second timeout. Eleven initial 128-rank diagnostic attempts used the
driver's mistakenly selected 256-task validation cap and failed during MPI
startup. Repeating only those launches with the established 512-task performance
cap passed all eleven. They are retained as **diagnostic infrastructure
failures**, not program failures. Neither the native profiles nor earlier
benchmark runs were changed.

The [existing Unstructured boundary supplement](2026-11-01-unstructured-boundary-validation.md)
remains required. This audit neither replaces its broader retrospective checks
nor extrapolates the 44 winners' successes to other implementations.

### 4. Affinity is configuration, not a hard resource boundary

The native launchers set CPU affinity and OpenMP thread counts, but the
validation/performance cgroups do not impose `AllowedCPUs`. The
[Matmul hybrid affinity helper](https://github.com/PeterTh/llm-eval-generated/blob/4500d708ad5c7b5d1594f93704011d6dfbca09a1/20260901-162328/matmul_claude-opus-5-cc-medium_hybrid_r2/matmul/matmul.cpp#L480) explicitly widens its
mask before repartitioning local physical cores; the
[Nbody hybrid helper](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/nbody_claude-opus-5-cc-medium_hybrid_r3/nbody/nbody.cpp#L416) can similarly expand beyond the
inherited rank mask. The explicit `OMP_NUM_THREADS` setting remains respected.

This is a static enforcement gap, **not demonstrated extra-core use or an
unfair published measurement**. The benchmark's four × 32-thread allocation
already covers the node's 128 physical cores, whereas validation assigns fewer
cores. Runtime tracing would be needed to characterize actual placement changes.
A hard CPU-set policy would require a separate compatibility/fairness review.

## Valid or potentially acceptable deviations from the benchmark's spirit

These observations distinguish the measured task from a more general workload.
“Passes the current contract” should not be read as proof of unrestricted
semantic equivalence.

### Input-family specialization

**Black–Scholes, Sol 6 CUDA r3 and hybrid r5.** The generated options are scaled
versions of seven base contracts. The
[CUDA winner](https://github.com/PeterTh/llm-eval-generated/blob/32f1becd283322d1edff43dd47a3b3bc8e2cdad6/20260929-135931/black-scholes_gpt-6-sol-medium_cuda_r3/black-scholes/black_scholes.cpp#L71) exploits price homogeneity to evaluate
base prices and expand scaled copies; the
[hybrid winner](https://github.com/PeterTh/llm-eval-generated/blob/32f1becd283322d1edff43dd47a3b3bc8e2cdad6/20260929-135931/black-scholes_gpt-6-sol-medium_hybrid_r5/black-scholes/black_scholes.cpp#L230) evaluates the seven base prices
**before timing** and times their distributed GPU expansion. Both return the
tested prices, but their times should not be interpreted as pricing that many
independent arbitrary contracts. The MPI winner caches invariant coefficients
while retaining per-option log/CDF work; the OMP winner retains the full formula.

**Unstructured, CUDA/MPI/hybrid winners.** They replace general adjacency
traversal with arithmetic neighbors of the regular 2-D grid produced by the
only input generator. That matches this input family but does not demonstrate
general unstructured-mesh performance. The OMP winner retains compact adjacency
traversal.

**Roomsim, Sol 5.6 xhigh hybrid r3.** This is particularly important to expose
alongside the existing performance review. Its
[precompute kernel](https://github.com/PeterTh/llm-eval-generated/blob/e8d10c43d7fcdca42862537b0eb7d0d5fab6da66/20260805-120633/roomsim_gpt-5.6-sol-xhigh_hybrid_r3/roomsim/roomsim.cpp#L301) uses convexity of the generated
icosphere to omit octree visibility traversal: a chord between boundary points
cannot be occluded by a third boundary face. It still takes 16 samples per pair,
but [replaces the original random stream](https://github.com/PeterTh/llm-eval-generated/blob/e8d10c43d7fcdca42862537b0eb7d0d5fab6da66/20260805-120633/roomsim_gpt-5.6-sol-xhigh_hybrid_r3/roomsim/roomsim.cpp#L281) with
counter-based hash samples. Both the geometry shortcut and changed sampling
matter to interpretation. Passing the existing coarse final-distance checks
does not establish sample-by-sample equivalence.

**Roomsim, Sol 5.6 low OMP r1.** It computes each unordered triangle pair once
and mirrors the estimate. Physical reciprocity supports the symmetry, but the
Monte Carlo estimates are then correlated rather than separately sampled for
ordered pairs. The [existing individual review](individual/roomsim_gpt-5.6-sol-low_omp_r1.md)
already explains this. The current CUDA and MPI winners retain visibility
traversal and use jump-ahead to preserve the original random stream.

### Unobserved state and local-system assumptions

**Floyd–Warshall, Sol 5.6 xhigh CUDA r1 and MPI r5.** These compute distances
but omit the unobserved path/predecessor matrix. That matches the current
distance-only observable result; it does not perform all path-maintenance work
of the original input. The current hybrid and OMP winners retain path updates.
The hybrid winner also uses lossless bounded-distance encoding, enabled by the
specific positive bounded graph family.

**MPI/shared-memory work.** Cholesky MPI/hybrid, Floyd–Warshall hybrid, Matmul
hybrid and stencil hybrid use shared-memory windows on the single-node test
system. Matmul MPI creates deterministic input rows/columns locally before
timing and therefore avoids timed panel communication while still computing
the full dot products. These are legitimate local-system strategies, but they
should not be presented as evidence of multi-node communication scalability.

### Preparation versus timed computation

Cholesky CUDA and Cahn–Hilliard CUDA prepare execution graphs outside their
timed intervals. The graphs' actual factorization/evolution executes inside.
Matmul hybrid runs untimed CPU/GPU calibration trials to choose its split,
then recomputes the full timed product. GPU host-transfer boundaries also vary
among accepted implementations.

These are setup-amortization and timing-scope distinctions, not newly identified
missing synchronization. In particular, the Black–Scholes hybrid's untimed
seven-contract calculation deserves a clearer interpretation note than ordinary
buffer allocation or graph construction.

QT neighbor pruning, candidate reuse and avoiding a fully materialized quadratic
distance matrix were **not** classified as violations just because they do less
work. Such algorithmic optimization is part of the task, provided the required
greedy result and timing scope are preserved.

## Recommended next work

1. Prioritize stronger independent observation of Floyd–Warshall distances and
   stencil interior values. Additional shapes alone cannot close the demonstrated
   sparse-output blind spots. Design a validation-only observation/check that
   leaves the original inputs and timed programs unchanged; do not simply
   reinterpret all floating-point hash differences as errors.
2. Retain a small, deliberate input/topology suite: odd tails, noncubic grids,
   boundary propagation and identified fast-path triggers. The cases above
   are candidates, not newly adopted requirements.
3. For SpMV, retain targeted iteration-work review or separate work-count
   instrumentation. Its final-vector contract fundamentally cannot count repeats.
4. Surface the strongest workload distinctions in individual reviews, especially
   Roomsim hybrid's omitted visibility traversal and changed sampling.
   Any tightening of semantic eligibility needs an explicit policy decision.

There is no evidence here requiring a full benchmark rerun. A future confirmed
implementation failure should affect that implementation's appropriate validation
stage; any required measurement rerun should remain narrowly scoped.

## Reconstructing and extending the audit

From the artifact-repository root, verify the retained comparisons, winner set,
source bindings and counts without running benchmarks:

```bash
ruby analysis/src/winner_validity_audit/verify.rb --sources
```

Omit `--sources` if the separate generated-output Git repository is unavailable.
To reconstruct the 44-row coverage table with source links:

```bash
ruby analysis/src/winner_validity_audit/verify.rb --coverage
```

The [driver README](../src/winner_validity_audit/README.md) documents explicit
local-workspace reproduction. Neither verification command modifies the release
or launches a model. Failed startup logs are retained as bounded, hashed excerpts;
successful numerical output is retained in full.
