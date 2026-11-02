# Terra 6.1 XHigh in Codex: 20261102-030935

This completed batch contains 220 programs: all pass validation and benchmarking.
Its measurements are included in the [combined release](../../release/README.md)
and website, using the established benchmark settings, one warm-up and five
measurements per program. No benchmark retries were needed.

Generated-source commit: `c070881d4b6186c32117ecd339e87d6f32db77e7`.
Validation: 220 records, 220 passing all five stages.
See `summary.json` for backend counts and completed audit stages.
The [resolved audit](timing-audit/resolved-selection.json) combines primary,
independent and targeted reviews with the all-backend QT boundary review:
120 distinct programs, 98 valid intervals and 22 timing-only corrections.
No unresolved timing decisions remain. All ten Unstructured MPI/hybrid programs
also pass the supplemental boundary-sensitive external validation case.

`validation/records.jsonl` retains each result's metadata, staging provenance,
exact execution output, commands, exit statuses, wall times, and source-log
hashes. Successful compiler output is omitted; failure diagnostics remain.
`timing-audit/` retains inventories, exclusions, source-grounded findings,
independent reviews, adjudications, and compact attempt provenance.
Original generated code, transcripts, binaries, and build trees are not copied.

Every artifact is covered by `checksums.sha256`. Exact method files are under
`method/`; `method/layout.json` maps their stored paths to the experiment-repo
paths needed to reconstruct a runnable checkout. This avoids modifying frozen
code merely to accommodate the artifact repository's flat snapshot layout.

## Timing-only corrections

22 programs now have accepted, revalidated timing-only corrections.
Both original and corrected Git revisions are retained in the
[correction registry and report](timing-corrections/README.md).
All 22 corrected programs pass revalidation with unchanged numerical output.
The other 198 programs retain their original source. Benchmark records identify
the measured source version and retain both Git links for corrected programs.

## Accounting and comparison

Exact native Codex usage is retained in
[`metadata/codex-usage/20261102-030935.jsonl`](../../metadata/codex-usage/20261102-030935.jsonl).
The [pricing note](../../analysis/notes/2026-10-29-terra61-pricing.md) explains the
shared frozen Terra rates and request-context verification. Costs are API-equivalent
estimates, not subscription charges.

The [winner comparison](../../analysis/notes/2026-11-02-terra61-xhigh-codex-winner-context.json)
finds no new cell winners. All 8,360 prior observations remain unchanged; joint
scoring thresholds update 121 prior scores.
