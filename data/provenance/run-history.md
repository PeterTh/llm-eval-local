# Run and Correction History

## Canonical run: `20260819-003427`

The complete run contains 4,620 validation records, 3,825 fully valid programs,
3,825 benchmark attempts, 3,488 benchmark successes, 337 benchmark failures, and
4,620 canonical scores. Its manifest SHA-256 is `3634bc842a57e1681ead78d74a90b26135b6efee698e6276521328a98dfd9496` and frozen
benchmark configuration SHA-256 is
`20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970`.

An initially successful SpMV record reported `0.000 ms` because generated code
passed a float buffer to `MPI_Reduce` as `MPI_DOUBLE`. Two immutable amendments
hardened positive-time parsing and isolated exact-ID resume reconciliation. Only
`spmv_gpt-5.6-terra-low_hybrid_r2` was rerun; all 3,824 unrelated benchmark
records retained their original digest. The prior attempt is preserved under
`data/benchmark/attempts/`.

Final scored YAML SHA-256: `9181253b486980ef1bbec72ff99eb2e58e6ade3df40abc419f1e2eb9a368d9ee`.

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
