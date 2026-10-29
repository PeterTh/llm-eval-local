# Terra 6.1 Medium in Codex: 20261028-200951

This completed batch contains 220 programs: all pass validation and benchmarking.
Its measurements are included in the [combined release](../../release/README.md)
and website, using the established benchmark settings, one warm-up and five
measurements per program.

Generated-source commit: `c94e9a7be1efbb0235af8cd31fdb9f5c7b994a36`.
Validation: 220 records, 220 passing all five stages.
See `summary.json` for backend counts and completed audit stages.
The [resolved audit](timing-audit/resolved-selection.json) combines primary,
independent and targeted reviews with the all-backend QT boundary review:
120 distinct programs, 94 valid intervals and 26 timing-only corrections.
No unresolved timing decisions remain.

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

26 programs now have accepted, revalidated timing-only corrections.
Both original and corrected Git revisions are retained in the
[correction registry and report](timing-corrections/README.md).
All 26 corrected programs pass revalidation with unchanged numerical output.
The other 194 programs retain their original source. Benchmark records identify
the measured source version and retain both Git links for corrected programs.

## Accounting and comparison

Exact native Codex usage is retained in
[`metadata/codex-usage/20261028-200951.jsonl`](../../metadata/codex-usage/20261028-200951.jsonl).
The [pricing note](../../analysis/notes/2026-10-29-terra61-pricing.md) explains the
frozen API-equivalent rates and request-context verification. These are not
subscription charges.

The [winner comparison](../../analysis/notes/2026-10-29-terra61-codex-winner-context.json)
finds no new cell winners. All 7,920 prior observations are unchanged; joint
scoring thresholds update 153 prior scores.
