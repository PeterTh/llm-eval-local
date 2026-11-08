# Fable 5.1 Medium in Claude Code: 20261011-092100

All 220 programs pass validation and have successful benchmark measurements.
Results are included in the [combined release](../../release/README.md) and
website using the established 44 benchmark cells, one warm-up and five samples.
The four backend canaries are reused; no historical observations or completed
measurements were rerun.

The [validation records](validation/records.jsonl) include the applicable
strengthened external checks. The [static SpMV review](validation/spmv-work-count/export.json)
covers all 20 implementations with no work-count failures.

## Timing-only corrections

The [resolved audit](timing-audit/resolved-selection.json) covers 120 distinct
programs across MPI/hybrid and the all-backend QT boundary review: 51 valid
intervals and 69 timing-only corrections, with no unresolved decisions.
All corrections passed independent review and native scientific revalidation.
The other 151 programs retain their original source. Both original and corrected
Git revisions are accessible through the
[correction registry and report](timing-corrections/README.md); benchmark records
identify the measured revision. Superseded correction proposals and reviews are
retained compactly in [revision history](timing-corrections/revision-history/export.json).

## Accounting and comparison

The native Claude Code profile uses medium effort under the shared harness.
The [pricing note](../../analysis/notes/2026-11-08-fable51-pricing.md) describes
accepted-attempt token accounting and frozen API-equivalent rates, not
subscription charges. Provider-failed attempts and quota waits are retained in
provenance and excluded from accepted generation times.

The [winner comparison](../../analysis/notes/2026-11-08-fable51-medium-winner-context.json)
identifies three new winners, each with an individual review: Cholesky hybrid,
QT clustering OpenMP and N-body OpenMP. Limited explanatory probes for the two
outliers are separate from benchmark measurements. All 8,800 prior observations
remain unchanged; joint scoring updates 263 prior overall scores.

## Retained evidence

Validation output, source/method bindings, independent reviews, correction
decisions, measurements and compact generation/pricing provenance are retained.
Generated programs and transcripts remain in the source repository; binaries,
build trees and successful bulk numerical arrays are not copied. Method layouts
reference shared files by digest, and `checksums.sha256` covers the evidence.
