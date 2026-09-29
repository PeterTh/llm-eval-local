# Benchmark monitoring notes

## 2026-09-28 17:14 UTC

The persistent `claude5-benchmark-20260928.service` is active, PID 3183621.
104/642 records completed, 102 successful. Scratch has 104 GiB free; home has
2.3 TiB free. The campaign remains in the unchanged-program phase.

- `black-scholes_claude-sonnet-5-cc-medium_hybrid_r3`: warm-up failed at
  `-n 100000000` / four ranks. Stderr contains an invalid-address error and
  segmentation fault inside MPI_Gatherv, followed by the 30-second timeout.
  Static source inspection identifies integer byte displacement multiplication
  at `black-scholes/black_scholes.cpp:355-356` (followed by MPI_BYTE Gatherv
  at lines 360-362). The received per-rank byte count is 1,800,000,000;
  later rank byte displacements exceed a signed 32-bit int. This is consistent
  with a generated-program size-dependent gather bug, not a timing correction
  or infrastructure problem. No algorithmic correction or retry authorized.
- `cahn-hilliard_claude-fable-5-cc-medium_omp_r4`: warm-up exceeded the frozen
  30-second timeout for `-x 512 -i 30`. No further stderr beyond the timeout.
  Retain as a benchmark failure; no size, iteration or timeout adjustment.

The other completed measurements remain untouched. No infrastructure failure
or campaign-wide validity problem was observed. Continue the frozen campaign.

## 2026-09-28 18:14 UTC

Service remains active, 185/642 completed and 181 successful; storage unchanged.

- `cholesky_claude-fable-5-cc-medium_omp_r3`: warm-up exceeded the established
  39-second timeout at `-n 4992`; no other stderr diagnostic.
- `cholesky_claude-opus-5-cc-medium_mpi_r4`: warm-up failed after 14.0 seconds
  at `-n 3072`, exit 153 / SIGXFSZ (file size limit exceeded) on rank 0.
  The source uses `MPI_Win_allocate_shared` for `n*n*sizeof(double)` at
  `cholesky/cholesky.cpp:749-754`, which is 72 MiB for this input, exceeding
  the unchanged 64-MiB file-size limit when MPI backs the allocation with a
  shared-memory file. This is a resource-limit interaction, not a numerical
  failure or demonstrated algorithmic defect. Retain the failure and its logs
  under the established procedure; do not silently relax limits or rerun.
  Any future protocol change should explicitly scope and document this case
  and other affected shared-memory users, without repeating unrelated results.

## 2026-09-28 19:13 UTC

247/642 completed, 242 successful; service active and free storage unchanged.
The only additional failure is `floydwarshall_claude-opus-5-cc-medium_omp_r5`:
warm-up timed out after the established 30 seconds at `-n 8704`, with no
other stderr diagnostic. Continue without changing or repeating measurements.

## 2026-09-28 20:12 UTC

334/642 completed, 322 successful; service active and storage healthy. All seven
new failures are warm-up timeouts with no additional stderr diagnostics:

- `matmul_claude-sonnet-5-cc-medium_omp_r4`: `-n 8832`, 48 seconds.
- `qtclustering_claude-sonnet-5-cc-medium_cuda_r3` and `_r4`: `-n 7800`, 84 seconds.
- `qtclustering_claude-sonnet-5-cc-medium_omp_r1`, `_r3`, `_r4`, `_r5`:
  `-n 6200`, 30 seconds.

No configuration change, rerun or infrastructure recovery is warranted by these
records. Continue the campaign; historical measurements remain untouched.

## 2026-09-28 21:11 UTC

412/642 completed, 399 successful; service active and storage healthy. New failure:
`spmv_claude-fable-5-cc-medium_omp_r1`, warm-up timeout after 30 seconds for
`-n 5000 -s 40 -i 50000`, without other stderr diagnostics. The unchanged
partition has 56 programs left; monitor the source-amendment transition more
closely. No reruns or configuration changes have been performed.

## 2026-09-28 22:05 UTC — source transition verified

All 468 unchanged programs completed: 453 successful, 15 failed. Two additional
warm-up timeouts at `-n 5000 -i 134` / 40 seconds were observed since 21:11 UTC:
`unstructured_claude-fable-5-cc-medium_omp_r3` and
`unstructured_claude-sonnet-5-cc-medium_omp_r4`.

The driver recorded the 468-record unchanged partition guard and advanced only
the isolated execution checkout from `db27e2872a28b900024d318f6a3004a3a7fddfa7`
to `4500d708ad5c7b5d1594f93704011d6dfbca09a1`. The immutable source amendment
covers exactly 174 IDs, SHA-256:
`4ab7b8e012437d75654c73cfe7196c08f285644affcc82cdc38dcd7591af5186`.

The first corrected program, `black-scholes_claude-fable-5-cc-medium_hybrid_r1`,
built and benchmarked successfully. Inspected metadata binds `timing_fixed: true`,
the amendment digest, both source commits/digests, issue categories and changed
paths. Execution labels are warmup then 0..4; the configuration digest is unchanged.
Its five recorded times are 185.132, 185.028, 185.594, 184.654 and 180.248 ms.
The original results were not repeated. Return to approximately hourly monitoring.

## 2026-09-28 23:04 UTC

517/642 completed, 500 successful. The corrected phase has completed 49 programs,
47 successfully. Service active; storage healthy. The two new failures both
compiled successfully and carry timing-fixed/source metadata:

- `matmul_claude-opus-5-cc-medium_hybrid_r2`: `-n 8192`, SIGXFSZ / exit 153
  in warm-up. Source uses MPI_Win_allocate_shared at `matmul/matmul.cpp:692-696`.
- `matmul_claude-opus-5-cc-medium_mpi_r4`: `-n 6144`, SIGXFSZ / exit 153
  in warm-up. Source allocates a shared B matrix using MPI_Win_allocate_shared
  at `matmul/matmul.cpp:266-268`; the matrix alone is 288 MiB.

These match the existing 64-MiB shared-memory backing-file limit interaction
seen in the Cholesky case. Preserve this distinct failure category and the
established configuration. Any relaxation requires an explicit protocol decision
and only an affected-program rerun, not a full campaign restart.

## 2026-09-29 — final monitoring and completion

- 00:03 UTC: 560/642 complete, 543 successful; no new failures.
- 01:03 UTC: 594/642 complete, 577 successful; no new failures.
- 02:03 UTC: 635/642 complete, 618 successful; no new failures.
- 02:14:15 UTC: all 642 complete, 624 successful and 18 failed. The driver
  verified the unchanged 468-record partition and exited successfully.

The final additional failure was `unstructured_claude-sonnet-5-cc-medium_hybrid_r5`:
successful corrected-source build, then a warm-up timeout at the unchanged
`-n 7000 -i 4000` / 30-second limit. No other stderr diagnostic.

Final failure categories: 14 timeouts, one MPI gather crash followed by timeout,
and three SIGXFSZ shared-memory/file-limit interactions. All 174 corrected-source
builds succeeded; 171 corrected benchmarks succeeded. No infrastructure recovery,
benchmark retry, validation rerun, recalibration or historical measurement change
was performed. The three invocations scheduled 4 + 464 + 174 new programs, with
the four canaries retained rather than repeated. Total campaign elapsed time
from first canary invocation was approximately 10 hours 16 minutes.
