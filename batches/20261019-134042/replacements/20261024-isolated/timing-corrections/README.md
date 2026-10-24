# Timing-only corrections: 20261019-134042

6 accepted corrections; all 6 corrected programs passed
the unchanged five-stage validation and performance benchmarking.
The original validation and audit findings remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `2c84ee55733daf9fc48a869e5d1f4a068f404f1f`.
Corrected source commit: `ce4a44804c3a5dca64f03c4ec524df959238940f`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the benchmark exports and current scored release.
The website displays both commit-pinned source links for timing-corrected runs.
Both source revisions are published in the generated-output repository.

Exact proposals, independent decisions, compile outcomes, validation outputs,
method snapshots and compact attempt metadata are retained. Raw agent streams,
binaries, build trees, full generated sources and reproducible aggregate patches
are omitted. `proposal-snapshot-reconstruction.json` describes reconstruction
of omitted duplicate proposal snapshots; original manifests retain their hashes.
`method/layout.json` maps stored snapshots to their experiment-repository paths.
`validation-comparison.jsonl` additionally compares the exact numerical result
blocks with the original validation, excluding timing and performance output.
Byte identity is supplementary evidence, not a replacement for the unchanged
numerical validation criteria.
