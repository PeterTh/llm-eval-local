# Timing-only corrections: 20261017-192226

14 accepted corrections; all 14 corrected programs passed the unchanged five-stage
validation and the established benchmark procedure. Original validation, audit
findings and historical measurement observations remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `352c09d57e14ef93744aa8cc741ff52884079e5f`.
Corrected source commit: `9012afd8480bb000ff7b01581a91c6b680ef2394`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the benchmark export and combined scored release.
The website displays both commit-pinned source links for timing-corrected runs.

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
