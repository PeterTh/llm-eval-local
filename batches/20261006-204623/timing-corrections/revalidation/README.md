# Supplementary validation and timing audit: 20261006-204623

This batch has validation and, when present, static timing-audit evidence only.
It has not been benchmarked or scored and is not merged into the historical
canonical dataset or its website's performance results.

Generated-source commit: `8bfe74f8bfb8397f57f524c7e8b5981a985253f7`.
Validation: 11 records, 11 passing all five stages.
See `summary.json` for backend counts and completed audit stages.
When finalized, the human-readable findings and proposed next steps are in
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
