# Timing-only corrections: 20261025-170121

45 accepted corrections; all 45 corrected programs passed
the unchanged five-stage validation. No performance benchmark was run.
The original validation, audit findings and historical scored release remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `74652eee82e2473660a7e75f3ad5d77fd0e3759c`.
Corrected source commit: `cbe8dcd9a86fdc63b7c5f62980956f015725ccfc`.
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
