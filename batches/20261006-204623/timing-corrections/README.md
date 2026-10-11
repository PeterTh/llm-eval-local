# Timing-only corrections: 20261006-204623

11 accepted corrections; all 11 corrected programs passed
the unchanged five-stage validation and subsequent performance benchmarking.
The original validation and intermediate audit findings remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `6adaf64dc195651e5b3da3575738874e09fdc72d`.
Corrected source commit: `8bfe74f8bfb8397f57f524c7e8b5981a985253f7`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the batch's benchmark records; the website displays
both commit-pinned source links and the timing-fix flag. The combined release
uses the corrected measurements. `summary.json` records the state at correction
export; the enclosing batch summary records the completed benchmark phase.

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
