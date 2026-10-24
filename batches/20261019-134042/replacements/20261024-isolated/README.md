# Scoped validation, timing audit and benchmarks: 20261019-134042

This batch supplies 24 observations to the current release. All 24 were
validated; 23 passed and were benchmarked with the established sizes and
measurement procedure. The remaining numerical-validation failure is retained
without a performance result. The release catalog selects these observations
alongside the 196 unchanged observations in the parent batch.

Generated-source commit: `2c84ee55733daf9fc48a869e5d1f4a068f404f1f`.
Validation: 24 records, 23 passing all five stages.
See `summary.json` for backend counts and completed audit stages.
The human-readable findings are in
[the audit report](timing-audit/primary/final/report.md), and machine-readable
decisions in `timing-audit/primary/final/decisions.jsonl`. An ambiguous decision
has `timing_review_required: true` and `timing_fix_required: null`, not a pass.

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

6 programs now have accepted, revalidated timing-only corrections.
Both original and corrected Git revisions are retained in the
[correction registry and report](timing-corrections/README.md).
All 6 corrections passed revalidation and are included in the 23 successful
benchmarks. The benchmark records retain the exact inputs, resources and samples.
