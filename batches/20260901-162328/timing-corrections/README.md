# Timing-only corrections: batch 20260901-162328

174 accepted corrections; all 174 corrected programs passed
the unchanged five-stage validation. No performance benchmark was run.
The original validation, audit findings and historical scored release remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `db27e2872a28b900024d318f6a3004a3a7fddfa7`.
Corrected source commit: `4500d708ad5c7b5d1594f93704011d6dfbca09a1`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to future benchmark exports; the existing website
already displays both commit-pinned source links for timing-corrected runs.
This batch is not yet merged into website performance results. Publishing the
corrected commit and integrating benchmark/scoring data remain separate steps.

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
