# Supplementary validation, timing audit and benchmarks: 20260901-162328

This batch retains validation, static timing-audit, timing-correction and benchmark
evidence. Benchmarking completed on 2026-09-29: 627/642 successful. It is included in
the combined release and website performance views. Historical raw data is preserved.
See the [benchmark report](benchmark/README.md) for unchanged settings and failures.

Generated-source commit: `db27e2872a28b900024d318f6a3004a3a7fddfa7`.
Validation: 660 records, 642 passing all five stages.
See `summary.json` for backend counts and completed audit stages.
The human-readable findings and proposed next steps from the static audit are in
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

174 programs now have accepted, revalidated timing-only corrections.
Both original and corrected Git revisions are retained in the
[correction registry and report](timing-corrections/README.md).
The correction/audit reports are snapshots of their earlier, pre-benchmark phases.
The [benchmark records](benchmark/README.md) now include timing-fixed flags and both
source links for all 174 corrected programs. The two originally conditional timing
findings are explicitly accepted only for the frozen benchmark configuration;
their original audit findings have not been overwritten.

## Integration

`aggregate/` retains the exact 660-row native aggregate CSV, freshness metadata and
export receipt. The combined scores and 24 new-winner comparisons are under
[`../../release/`](../../release/README.md); individual analyses are under
`../../analysis/notes/individual/`. Joint rescoring changes thresholds, not measurements.
`benchmark/method/pipeline-layout.json` maps the final pipeline to the original method
snapshot plus the single amended file, avoiding another full source copy.
