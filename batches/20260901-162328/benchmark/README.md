# Benchmark results — batch 20260901-162328

Results finalized 2026-09-29 at 09:53 UTC (11:53 CEST). All 642 validation-passing
programs were benchmarked: **627 succeeded and 15 failed**. The initial campaign
completed at 02:14 UTC; three targeted retries subsequently succeeded, with all
639 unrelated records verified unchanged.

| Model | Valid programs benchmarked | Successful | Failed |
| --- | ---: | ---: | ---: |
| Fable 5 | 214 | 210 | 4 |
| Opus 5 | 218 | 217 | 1 |
| Sonnet 5 | 210 | 200 | 10 |
| Total | 642 | 627 | 15 |

Backend successes: CUDA 159/161, hybrid 158/160, MPI 164/164, OpenMP 146/157.
All 174 timing-corrected sources built successfully; 173 benchmarked successfully.
The 18 programs that failed original validation were not benchmarked.

## Procedure and provenance

All 44 benchmark/backend cells were inherited unchanged from the historical frozen
run `20260819-003427`: problem sizes, iteration counts, timeouts, target settings,
resource profiles, one warm-up and five recorded repetitions. No validation or
calibration was repeated. The existing measurement code was unchanged.
Temporary builds were on local `/tmp`; persistent logs/results are
under home. No tests or qualification runs overlapped measured benchmarks.

Historical configuration SHA-256:
`20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970`.
New configuration SHA-256:
`6ce918524cac238dfb3f05b7a3817a1c361910c0c76f5f7b4efbd4bc9576517d`.
Only run/validation/seed-path bindings and inheritance provenance changed. Every
measurement cell and target setting was compared equal before and after the run.

Four initial representative measurements were retained in the 468 unchanged-source
results, not repeated. Those 468 records were hash-guarded before applying the
existing source-correction amendment for the remaining 174 programs. The initial
completion check proved that partition remained identical. The initial invocations
scheduled 4 + 464 + 174 new programs. The subsequent scoped retries scheduled only
1 + 2 previously failed programs. No historical benchmark record changed.

Original source commit: `db27e2872a28b900024d318f6a3004a3a7fddfa7`.
Corrected source commit: `4500d708ad5c7b5d1594f93704011d6dfbca09a1`.
Corrected records carry `timing_fixed: true`, both source commits/digests/URLs,
issue categories, build provenance and the immutable amendment digest. Originals
remain in Git; the corrected commit has not been pushed or published.

Both conditional Floyd-Warshall hybrid timers satisfy their guards at `-n 10240`
with four ranks. See [configuration-specific decisions](conditional-timing-decisions.jsonl)
and [source-grounded rationale](campaign/README.md). Neither source nor original
conditional audit finding was changed.

## Remaining failures

[The failure index](failures.jsonl) and `failures/<id>/` retain all diagnostics.

- **14 timeouts** under the established benchmark limits. These remain failed
  measurements; sizes and limits were not adjusted to obtain passes.
- **One MPI gather crash**: Sonnet 5 Black-Scholes hybrid r3. At 100 million
  options, its signed-integer byte-displacement calculations overflow for later
  ranks; the observed invalid-address/segmentation fault in MPI_Gatherv is consistent
  with this source defect. The timeout subsequently terminated the failed job.

Superseded attempts and internal retry provenance are retained separately from
the current failure index. No generated program was modified for these retries.

## Retained artifacts

`records/<benchmark>/<backend>.jsonl` uses the existing benchmark-record schema.
Canonical result maps, execution wall times, invocation metadata, frozen settings,
source amendment, partition guard, conditional decisions and failure logs are kept.
`evidence-index.jsonl` retains all source-log hashes and native metadata key order.
The exporter proves that each original `benchmark_metadata.yaml` can be reconstructed
byte-for-byte from its structured record, the existing validation manifest, and that
key order. No second full copy of native metadata is necessary.

`reconstruction.json` also identifies the existing correction registry and pipeline
snapshots used to avoid duplicating large evidence files. Successful raw stdout,
compiler output, binaries, build trees and generated-source copies are omitted.
Both the benchmark subtree and the complete supplementary batch have checksum
manifests. The native results remain under
`/home/petert/llm_para_local_evaluation/20260928-claude5-validation`.

The historical canonical release, scores and website dataset remain unchanged.
Scoring, website integration, source publication, commits and pushes were not part
of this benchmark step.
