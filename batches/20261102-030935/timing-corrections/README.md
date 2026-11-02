# Timing-only corrections: 20261102-030935

22 accepted corrections; all 22 corrected programs passed
the unchanged five-stage validation and subsequent performance benchmarking.
The original validation and audit findings remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `c070881d4b6186c32117ecd339e87d6f32db77e7`.
Corrected source commit: `db69dadaac5ae1d55b85e40af2cf6a59e07cf7e4`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the batch's benchmark records and combined release;
the website displays both commit-pinned source links for timing-corrected runs.
Both source revisions are published in the generated-program repository.

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
