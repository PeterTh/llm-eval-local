# Opus 5.5 Medium: 20261002-142720

This completed campaign contributes 220 programs to the combined release: 219
passed scientific validation and all 219 benchmarked successfully. The one MPI
Cahn–Hilliard backend-classification failure remains invalid. Benchmarking used
the unchanged inherited sizes, one warmup and five measurements, with no retries.

Generated-source commit: `d2d8446a37657d114b3ea1c171767218539cae54`.
Validation: 220 records, 219 passing all five stages.
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

83 programs now have accepted, revalidated timing-only corrections.
Both original and corrected Git revisions are retained in the
[correction registry and report](timing-corrections/README.md).
Benchmark records and native provenance are in `benchmark/`; the exact native
aggregate CSV is in `aggregate/`. The canonical release applies the joint scoring
procedure to these observations without re-executing programs.

The MPI/hybrid audit covers 109 validated programs; the QT-specific audit covers
all 20 QT implementations, including preprocessing boundaries. Stronger-model
adjudication resolved ambiguous cases before corrections. The additional QT review
identified no corrections beyond the 83 accepted timer fixes.

`generation/observations.jsonl` retains exact usage counters and transcript hashes
for all 220 runs. The pinned Claude Code 2.1.287 configuration is under
`generation/method/`; compact supervision amendments and completion checks retain
operational provenance. Generated programs and full transcripts remain only in
the generated-source repository. Result Hash fields do not add a validation gate
beyond the established scientific comparison.
