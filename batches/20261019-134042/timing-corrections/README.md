# Timing-only corrections: 20261019-134042

This native evidence set retains 57 accepted timing-only corrections; all 57
passed the unchanged five-stage validation and subsequent benchmarking.
The current release selects 50 of these corrections and 6 from the
[scoped observation set](../replacements/20261024-isolated/timing-corrections/).
The release catalog, not the archived native totals, defines the current view.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `40ad0bc6da259d4584e75b8f23f43c77e9751b24`.
Corrected source commit: `65363cf3710daa9e0d3409306efee5a49e18c8dd`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to the benchmark exports. The current website
displays both commit-pinned source links for each selected timing-corrected run.

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
