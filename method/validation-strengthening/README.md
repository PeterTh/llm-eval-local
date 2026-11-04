# Supplemental correctness method

The comparison policy and shape definitions here are the exact files used by the
retained supplemental evidence. They support read-only release verification;
the original measurement pipeline snapshot remains unchanged.

The native validator, retrospective drivers, export tools and tests are retained
in experiment commit
[`bdc4ade5d4ef733a78b7d999712a857c07ce191c`](https://github.com/PeterTh/llm-eval-experiment/tree/bdc4ade5d4ef733a78b7d999712a857c07ce191c).
This is the post-campaign code commit. Attempt receipts bind the actual files
used during the sweep, including earlier revisions, by content hash.

See the [research note](../../analysis/notes/2026-11-04-validation-strengthening.md)
for coverage, exclusions and limitations, and the experiment's
[driver instructions](https://github.com/PeterTh/llm-eval-experiment/blob/bdc4ade5d4ef733a78b7d999712a857c07ce191c/tools/validation_audit/README.md)
for controlled reproduction. Reproduction is correctness work, never a replacement
performance measurement. No generated or sequential benchmark source is copied here.
