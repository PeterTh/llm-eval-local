# Terra 6.1 Ultra in Codex: 20261105-131145

This completed batch contains 220 programs: 219 pass validation and
219 have successful benchmark measurements. Its results are included in the
[combined release](../../release/README.md) and website, using the established
benchmark settings, one warm-up and five measurements. The four backend
canaries are reused; no historical programs or completed measurements were rerun.

The retained validation failure is `cholesky_gpt-6.1-terra-ultra_mpi_r2`:
the existing backend classifier detects OpenMP as well as MPI. The generated
source and classification rule are unchanged. Complete outcomes and applicable
strengthened external checks are in [the validation records](validation/records.jsonl).
The [static SpMV review](validation/spmv-work-count/export.json) covers all
20 implementations with no additional work-count failures.

## Timing-only corrections

The [resolved timing audit](timing-audit/resolved-selection.json) covers 119
distinct programs across MPI/hybrid and the all-backend QT boundary review:
97 valid intervals and 22 timing-only corrections, with no unresolved decisions.
All 22 corrections passed independent review and scientific revalidation.
The other 198 programs retain their original source; the one validation failure
is not benchmarked. Both original and corrected Git revisions are available in
the [correction registry and report](timing-corrections/README.md), and each
benchmark record identifies the measured revision.

## Accounting and comparison

Ultra enables native delegation within the shared Codex harness and the same
access restrictions. The [recorded usage](../../metadata/codex-usage/20261105-131145.jsonl)
sums 18,126 unique requests across 220 parent and 645 child sessions.
All 220 generation tasks completed. For 49 observations, interrupted child
requests may have unrecorded usage, so their recorded token counts and costs
are explicitly marked as lower bounds. The [pricing note](../../analysis/notes/2026-10-29-terra61-pricing.md)
describes the shared frozen Terra rates and request-context evidence; these
are API-equivalent comparisons, not subscription charges.

The [winner comparison](../../analysis/notes/2026-11-06-terra61-ultra-codex-winner-context.json)
identifies 1 new cell winner, each with a source-pinned individual review. All 8,580 prior observations remain unchanged;
joint scoring thresholds update 31 prior scores.

## Retained evidence

Validation output, source and method bindings, independent reviews, correction
decisions, measurements, and compact generation/pricing provenance are retained.
Generated programs and transcripts remain in the generated-source repository;
binaries, build trees and successful bulk numerical arrays are not copied.
Method layouts reference shared files by digest, and `checksums.sha256` covers
this batch's retained artifacts.
