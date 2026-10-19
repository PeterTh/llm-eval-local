# Timing-only corrections: 20261018-224015

39 accepted corrections; all 39 corrected programs passed the unchanged five-stage
validation. All were benchmarked, with 29 successful measurements and ten retained
benchmark failures. Original validation and audit findings remain intact.
See [the correction report](final/report.md) and [registry](final/corrections.jsonl).

Original source commit: `fd64978a13b9a4f3ac6a5e368972316d0c159aa1`.
Corrected source commit: `fdf3ef5283428bb38fcfd6ec116e9fa03defe229`.
Every registry entry uses the established `timing_fixed`, `original_source_url`,
`corrected_source_url`, original/corrected commit/digest and issue-category fields.
These join by `program_id` to this batch's benchmark records; the website displays
both commit-pinned source links for timing-corrected runs. The original and
corrected source commits are published, and the batch is included in joint scoring.

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

For QT hybrid r3, matching result fields from multiple ranks appear in a different
order. Both outputs pass the native validator; the
[output-order record](../completion/revalidation-output-order-review.json) confirms
identical field multisets. No output repair or additional validation gate was applied.
