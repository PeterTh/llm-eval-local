# Timing-only corrections: 20261014-212207

All 71 timing-only corrections passed independent review and the unchanged
five-stage validation, then completed the established benchmark procedure.
Original validation and audit findings remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `8fe249fe2622f21b32faf8d13cd290ce902f78cd`.
Corrected source commit: `6196b2ba8d2509ff0a7ba87d17d846a479a39282`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the [benchmark records](../benchmark/); the website
displays both commit-pinned source links for timing-corrected runs.
The [batch overview](../README.md) summarizes the integrated results.

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
