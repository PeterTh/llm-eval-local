# Supplementary validation and timing audit: 20261002-142720

This directory retains the 83 successful corrected-source revalidations. Subsequent
benchmarking is retained in the parent batch's `benchmark/` directory and included
in the combined release and website.

Generated-source commit: `a14535a1a0101b4ddbc725d374772c2da529c824`.
Validation: 83 records, 83 passing all five stages.
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
