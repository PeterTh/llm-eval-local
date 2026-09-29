# Benchmark campaign — batch 20260901-162328

Prepared 2026-09-28 for the 642 programs passing original validation (out of 660).
All 174 accepted timing-only corrections also passed scoped revalidation. Neither
validation nor calibration is repeated for this benchmark campaign.

The 44 benchmark/backend cells, arguments, iteration counts, timeouts and target
settings are identical to historical run `20260819-003427`. Measurement code and
resource profiles are unchanged: one warm-up and five recorded repetitions,
128 physical cores for OpenMP/MPI, GPU 0 for CUDA, and four hybrid ranks with
32 cores and one node-local GPU per rank. Historical configuration SHA-256:
`20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970`.
New configuration SHA-256 (new provenance bindings only):
`6ce918524cac238dfb3f05b7a3817a1c361910c0c76f5f7b4efbd4bc9576517d`.

## Source and execution phases

1. Four unchanged Sonnet 5 Black-Scholes r1 programs (one per backend) are
   representative first measurements. These count toward the final set and are
   not repeated. Check their full metadata before authorizing the driver.
2. Complete the 468 unchanged valid programs from preserved validation binaries
   at original source commit `db27e2872a28b900024d318f6a3004a3a7fddfa7`.
3. Hash-guard those records and metadata; fast-forward only the isolated execution
   checkout to timing-corrected commit `4500d708ad5c7b5d1594f93704011d6dfbca09a1`.
4. Apply the established immutable source-correction amendment and benchmark only
   its 174 affected IDs. This existing path builds corrected sources in `/tmp` and
   records timing-fixed flags, both source commits/digests, and issue categories.
5. Verify exactly 642 final records and that all 468 unchanged records are intact.

The original validation manifest/results remain immutable. Corrected revalidation
is separately retained and bound by digest in `manifest.yaml`. Derived correction
evidence changes only checkout root paths and retains the accepted manifest hash;
all correction records and source/review provenance remain unchanged.

Original source backup for subsequent evidence verification:
`/tmp/claude5-benchmark-20260928-PQjWbg/original-source`.
Runtime/build scratch is node-local. Persistent results/logs are under
`/home/petert/llm_para_local_evaluation/20260928-claude5-validation`.

## Conditional timing findings resolved for this configuration

The historical audit verdicts remain conditional. These are configuration-specific
acceptance decisions, not source corrections or unconditional validity claims.
The frozen hybrid Floyd-Warshall cell uses `-n 10240`, with four MPI ranks.

- `floydwarshall_claude-fable-5-cc-medium_hybrid_r2`: the guard `N >= 4` is
  satisfied. Rank 0 owns the first rows and pivot, so the root-clock interval
  gates the first useful work and encloses completion. Original source lines
  102–120, 227–233 and 264–273 establish the ownership and timing/collective order.
- `floydwarshall_claude-opus-5-cc-medium_hybrid_r3`: the guard
  `ceil(N / 64) >= 4`, equivalently `N >= 193`, is satisfied: there are 160
  block rows. Rank 0 owns the first pivot block and gates computation after its
  timestamp. Original source lines 51, 537–548, 629–642 and 723–793 establish the
  block size, partition, start timestamp, first owner/broadcast and completion.

Both programs remain unmodified and benchmark-eligible under this pinned
configuration. Reassess these findings if the problem size or rank profile changes.

## Operations and retention

Run/status entry point: `tools/timing_audit/bin/benchmark_validation_batch.rb`.
The campaign runner is frozen by digest and can resume without repeating completed
consistent records. Its progress record distinguishes unchanged/corrected/complete
and stopped phases. Do not edit its frozen snapshot or provenance.

Monitor more closely initially and at the source transition, then approximately
hourly. Do not run code qualification/tests or heavy analysis concurrently with
measurement. Generated-program failures remain evidence; infrastructure or timing
validity failures require diagnosis and only affected measurements are eligible
for recovery. Never repeat the historical corpus or restart unrelated benchmarks.

After completion retain compact records, failure diagnostics, frozen settings and
source/provenance links in the supplementary artifact batch. Do not copy binaries,
build directories, generated sources or repetitive successful raw logs into Git.
This campaign does not authorize scoring, website deployment, pushes or tags.
