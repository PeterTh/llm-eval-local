# Run and Correction History

## Canonical run: `20260819-003427`

The complete run contains 4620 validation records,
3825 fully valid programs,
3825 benchmark attempts,  benchmark successes,
 benchmark failures, and 4,620 canonical scores. Its manifest
SHA-256 is `3634bc842a57e1681ead78d74a90b26135b6efee698e6276521328a98dfd9496` and frozen
benchmark configuration SHA-256 is
`20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970`.

An initially successful SpMV record reported `0.000 ms` because generated code
passed a float buffer to `MPI_Reduce` as `MPI_DOUBLE`. Two immutable amendments
hardened positive-time parsing and isolated exact-ID resume reconciliation. Only
`spmv_gpt-5.6-terra-low_hybrid_r2` was rerun; its prior attempt is preserved under
`data/benchmark/attempts/`.

A subsequent static audit examined all 1,615 successful MPI/hybrid programs under
the maximum-completed-rank-time contract. It classified 1,028 timings as valid and
587 as invalid. Timing-only corrections for those 587 programs were compiled,
independently reviewed, committed together, and rerun without replacing unrelated
results. 587 corrected benchmarks succeeded and
0 failed. All 3238 unrelated benchmark
records retained their original digest. The prior attempt is preserved under
the `local-eval-2026-08-22` Git tag; compact before/after measurements are in
`data/timing-audit/rerun-comparison.jsonl`.

Fifteen early records from the scoped batch were conservatively remeasured after
brief qualification activity overlapped their execution window. The exact IDs,
superseded-record digests, final-record digests, and unchanged-record guard are
retained under `data/provenance/scoped-measurement-rerun/`.

Final scored YAML SHA-256: `565e2eb10d55a27f0ed1e36d142a13a62768ac55ccb1558991b4708f1a9a8cfd`.

## Interrupted diagnostic runs

- `20260818-182827` was stopped after 2,027 validations because the then-current
  detector rejected four genuine CUDA-library answers. Its pipeline digest is
  intentionally stale and none of its corpus records are published here.
- `20260822-145159` was an unnecessary full replacement
  started before the localized-rerun policy was clarified. It was cleanly stopped
  at 925/4,620 validations (809 fully
  valid). Its one important new observation—the nondeterministic Cahn-Hilliard
  outcome—is retained as a scoped incident; unrelated duplicate records are not.

## Qualification evidence

The final host-enabled suite passed 70 runs / 520 assertions with no failures,
errors, or skips. A four-profile end-to-end canary completed validation,
calibration, benchmarking, aggregation, and scoring. Its diagnostic thresholds
and scores had no scientific meaning and therefore are summarized here rather
than copied as another dataset.
