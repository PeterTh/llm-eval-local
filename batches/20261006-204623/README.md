# Sol 6.1 medium and xhigh: 20261006-204623

This campaign adds 440 programs, 220 at each reasoning effort, to the
[combined release](../../release/README.md). Of these, 439 passed the unchanged
five-stage validation and all 439 completed benchmarking successfully. The one
native validation failure, `matmul_gpt-6.1-sol-medium_mpi_r1`, is retained without
repair or retry: its OpenMP SIMD directives trigger the established MPI target
classification rule.

Both profiles invoke `gpt-6.1-sol` through the shared Codex CLI harness.
The generation method, pinned executable version, observations, account-cleanup
records and exact-usage recovery receipt are under `generation/`. Recovered
counters for all 440 runs are retained once in
[`metadata/codex-usage/20261006-204623.jsonl`](../../metadata/codex-usage/20261006-204623.jsonl).
One failed provider-capacity attempt was excluded from generation time and only
that observation was retried; its compact metadata is preserved. The two
accepted preflight observations are included, not repeated.

## Validation and timing review

`validation/records.jsonl` retains all initial outcomes, staging provenance,
exact execution output, exit status, wall time and source-log hashes. Successful
compiler output is omitted; failure diagnostics remain.

Timing review covers 239 unique implementations: all 219 validated MPI/hybrid
programs and all 40 validated QT programs, with 20 in both groups. The final
decision set contains 228 valid and 11 timing-invalid programs, with no
unresolved cases. The ordered, digest-bound
[resolved selection](timing-audit/resolved-selection.json) composes the primary,
all-backend QT and supplemental MPI-split decisions. Earlier findings remain
intact; the primary report alone is not the final correction scope.

The supplemental decision for `qtclustering_gpt-6.1-sol-medium_hybrid_r2`
depends on the blocking world collective inside the pinned Open MPI 4.1.6
`MPI_Comm_split_type` implementation. Its compact source/compile proof and
installed-library digest are under `timing-audit/mpi-split-evidence/`; the
benchmark guard verified that library identity before measurement.

All 11 timing-only corrections compiled, received independent review and
passed unchanged revalidation. The
[correction registry](timing-corrections/final/corrections.jsonl) binds their
original and corrected sources:

- Original commit: `6adaf64dc195651e5b3da3575738874e09fdc72d`.
- Single correction commit: `8bfe74f8bfb8397f57f524c7e8b5981a985253f7`.

## Benchmarking and integration

The 439 successful measurements contain 428 unchanged programs and 11 corrected
ones, with no benchmark failures or retries. All 44 established cell sizes,
iteration counts, timeouts and resource profiles are unchanged. Every program
has one warmup and five measurements; accepted benchmark canaries were reused.
Structured records are under `benchmark/records/`, with configuration and
source-amendment evidence in `benchmark/provenance/`.

Seven new cell winners have [individual reviews](../../analysis/README.md#individual-implementation-reviews).
One bounded SpMV/MPI diagnostic explains its separated lead without replacing
canonical measurements. All 6,160 prior observations are unchanged; 97 prior
scores change solely through joint thresholds. Pricing uses the frozen
[Sol 6.1 Flex profiles](../../analysis/notes/2026-10-11-sol61-pricing.md).

Every scientific artifact is covered by `checksums.sha256`. Method layouts
map stored snapshots to their experiment-repository paths. The generation
layout maps original paths to artifact-root-relative files, reusing identical
method content and storing only new deltas. Every file is checked against the
original generation manifest. Generated programs
and transcripts remain in the source repository; binaries, build trees and
raw review-agent streams are excluded.
