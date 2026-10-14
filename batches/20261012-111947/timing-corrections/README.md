# Timing-only corrections: 20261012-111947

All 33 accepted timing-only corrections passed unchanged five-stage revalidation
and completed the established benchmark procedure successfully. Original validation
and audit findings remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `71ba7cc523997c8fd1537d7a8159b583f260793d`.
Corrected source commit: `778f868b8e30433e60115c46bf01dbf84c609765`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the [benchmark records](../benchmark/records/)
and combined scored release. The website displays both commit-pinned source links
for every timing-corrected run.

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
