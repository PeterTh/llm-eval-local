# Validation and timing audit — batch 20260901-162328

Completed 2026-09-28. No performance benchmarking or generated-source correction
was performed. The historical scored release and website dataset are unchanged.

Generated-source revision: `db27e2872a28b900024d318f6a3004a3a7fddfa7` in
`PeterTh/llm-eval-generated`. Validation manifest SHA-256:
`717d254ac272b32875618127ae10e2c4077057935f44694fa5011e668419732e`.

## Results

All 660 programs completed the existing five-stage validation process. Of these,
642 passed; all 324 passing MPI/hybrid programs received static timing review.
These are source-based timing classifications, not measurements of performance
impact. Passing validation does not itself establish timer correctness.

| Model | Validation passes | MPI/hybrid audited | Timing valid | Timing invalid | Conditional |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fable 5 | 214 / 220 | 109 | 28 | 80 | 1 |
| Opus 5 | 218 / 220 | 109 | 59 | 49 | 1 |
| Sonnet 5 | 210 / 220 | 106 | 61 | 45 | 0 |
| Total | 642 / 660 | 324 | 148 | 174 | 2 |

MPI: 164 audited, 84 valid and 80 invalid. Hybrid: 160 audited, 64 valid,
94 invalid and two conditional. The six validation-failing MPI/hybrid programs
are excluded explicitly, alongside the 330 out-of-scope CUDA/OpenMP programs.

Every invalid case has an individual source-grounded finding and a proposed
timing-only repair. The common defect is an unaggregated rank-local duration with
no proof that it encloses the complete global computation. A stop barrier alone
does not prove the root clock encloses work that began before its start timestamp.
All 174 invalid cases were independently reviewed; 134 additionally underwent
blind Sol adjudication. These are proposed correction candidates, not applied fixes.

`decisions.jsonl` and `decisions.csv` retain source hashes, all review verdicts,
decision basis, citations, conditions, and minimal correction proposals.
`correction-ids.txt` lists exactly the 174 confirmed candidates. Conditional cases
have `timing_fix_required: null` and `timing_review_required: true`; they are not
silently treated as passes or included in the confirmed correction list.

## Two size-dependent cases

Both cases are Floyd-Warshall hybrid programs under the recorded four-rank profile.
Their root clock encloses a global makespan only if rank 0 owns the first pivot.
Benchmark sizes have not yet been frozen, so validation sizes are not substituted
for the eventual benchmark configuration.

- `floydwarshall_claude-fable-5-cc-medium_hybrid_r2`: the proof holds for
  `numNodes >= 4`. With fewer nodes, rank 0 can own no initial rows and another
  rank can begin pivot preparation before rank 0's timestamp. See source lines
  102–120, 227–233 and 264–273.
- `floydwarshall_claude-opus-5-cc-medium_hybrid_r3`: with block size 64, the proof
  holds for `ceil(numNodes / 64) >= 4`, equivalently `numNodes >= 193`.
  Otherwise the first block owner may be non-root. See source lines 51,
  537–548, 629–642 and 723–793.

Resolve these against the frozen benchmark sizes before accepting their timing.
Alternatively, a separately approved timing-only change can make the timers
unconditional. The individual audit records retain proposed remedies.

## Validation failures

Per-backend validation passes were CUDA 161/165, hybrid 160/165, MPI 164/165,
and OpenMP 157/165. The 18 failures consist of:

- One backend-detection rejection: `black-scholes_claude-opus-5-cc-medium_cuda_r5`
  also uses OpenMP pragmas, violating the unchanged pure-CUDA classification rule.
- Sixteen numerical mismatches: 15 RoomSim implementations and
  `qtclustering_claude-sonnet-5-cc-medium_omp_r2`. The existing reference inputs
  and tolerances were retained. Exact output and diagnostics are in the validation
  records; these are not network or server failures.
- One execution failure: `stencil3d_claude-sonnet-5-cc-medium_hybrid_r2` overrides
  the supplied thread count and requests 64 OpenMP threads per rank. Four ranks
  plus MPI/CUDA overhead exceed the existing 256-task validation limit, producing
  thread-creation errors. It remains a failure under the recorded resource profile;
  no special resource exception or identical retry was used to turn it into a pass.

No validation was repeated. There were no unresolved infrastructure failures.

The software test suite passed with 99 tests and 729 assertions, zero failures
or errors, and three expected skips. The generated-source repository remains at
the pinned revision with no tracked modifications.

## Review method and quality checks

1. A stratified 16-case Luna/high pilot ran with four workers. The main investigator
   inspected each timer and called computation path before approving expansion.
2. The pilot exposed false positives for root-controlled scatter/pivot/panel
   dependencies. Three blind Sol checks using the original guidance did not fix
   that weakness. Refined guidance explicitly traces the first useful work and
   global completion; a five-case blind Luna check matched all source inspections.
3. The full primary stage reviewed 324 programs with 16 Luna/high workers:
   102 valid, 221 invalid, one ambiguous. These screening verdicts were not final.
4. Refined independent Luna/high review covered all 222 flagged, uncertain, and
   valid-without-MPI_MAX cases: 47 valid, 174 invalid, one ambiguous.
   There were 48 verdict disagreements; category/fixability differences and
   unresolved uncertainty expanded blind Sol/xhigh adjudication to 181 cases.
5. Those adjudications produced 45 valid, 134 invalid and two ambiguous findings.
   A final source check selected one additional blind Sol review:
   `spmv_claude-opus-5-cc-medium_hybrid_r1`. Earlier findings assumed multiple GPUs
   per rank. The actual wrapper exposes one device per rank, forcing one device
   worker; the complete local interval is correctly MPI_MAX-reduced. The
   supplemental review classified it valid. Both original findings are preserved.

Workers received source dossiers and, where applicable, frozen static platform
facts, but no earlier verdicts. Execution tools, web search, hooks and integrations
were disabled; accepted event streams were checked for prohibited tool events.
The main investigator used one compile-only ABI probe to confirm that the target
chrono millisecond count has type `long`, matching `MPI_LONG`. No probe executable
or generated program was run during the static audit.

An initial event checker incorrectly rejected the CLI's tool-disabled diagnostic.
The checker was corrected; eight completed responses were recovered without new
model calls. Original evidence and unused-attempt provenance remain under
`recovery/`. Citation-format and API-capacity failures were retried only for the
affected record. No model response was manually edited into a passing result.

The OpenAI Docs skill informed the tools-disabled worker configuration, checked
against local Codex capabilities and the official configuration reference:
https://learn.chatgpt.com/docs/config-file/config-reference.

## Retention and proposed next step

Compact evidence is under `llm-eval-local/batches/20260901-162328`, with frozen
method snapshots, validation logs, inventories/exclusions, review results,
attempt metadata, final decisions and checksums. Generated code, transcripts
already retained in the source repo, binaries, build trees and repeated raw agent
streams are not duplicated. Persistent working evidence remains under home;
temporary work uses local storage, not NFS. No commit or push was performed.

The next separately authorized phase would prepare and independently verify
timing-only patches for the 174 confirmed candidates, resolve the two conditions,
and commit accepted generated-source changes together. Repairs should preserve
algorithms, initialization, iteration counts and output semantics, aggregate
complete per-rank times with matching MPI datatypes, and make the canonical
reported metric use that aggregate. Record which programs required correction.
Any subsequent rerun should be scoped to affected programs; this audit does not
justify re-executing unrelated historical benchmarks.
