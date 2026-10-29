# Timing-only corrections: 20261028-200951

26 accepted corrections; all 26 corrected programs passed
the unchanged five-stage validation and subsequent performance benchmarking.
The original validation and audit findings remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `c94e9a7be1efbb0235af8cd31fdb9f5c7b994a36`.
Corrected source commit: `6e8d51b08ba6dd1a9bf75a659920c05831829bec`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the [benchmark records](../benchmark/records/).
The combined release and website include the corrected measurements and display
both commit-pinned source links for timing-corrected runs.

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
