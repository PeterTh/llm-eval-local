# Supplemental correctness method

The comparison policy and shape definitions here are the exact files used by the
retained supplemental evidence. They support read-only release verification;
the original measurement pipeline snapshot remains unchanged.

The native validator, retrospective drivers, export tools and tests are retained
in experiment commit
[`6962baaca7b9c511a07d680b7c1bf8bd523fe7d2`](https://github.com/PeterTh/llm-eval-experiment/tree/6962baaca7b9c511a07d680b7c1bf8bd523fe7d2).
This is the post-campaign code commit. Attempt receipts bind the actual files
used during the sweep, including earlier revisions, by content hash.

See the [research note](../../analysis/notes/2026-11-04-validation-strengthening.md)
for coverage, exclusions and limitations, and the experiment's
[driver instructions](https://github.com/PeterTh/llm-eval-experiment/blob/6962baaca7b9c511a07d680b7c1bf8bd523fe7d2/tools/validation_audit/README.md)
for controlled reproduction. Reproduction is correctness work, never a replacement
performance measurement. No generated or sequential benchmark source is copied here.

The [complete-array findings](../../analysis/notes/2026-11-04-full-array-validation.md)
and [full export](../../validation-supplements/20261105-full-array-full/export.json)
retain the later floating-result sweep and its source-bound observer reviews.
Future native validation includes that numerical comparison after the ordinary
and supplemental checks. The [native integration smoke proof](../../validation-supplements/20261105-native-full-array-smoke/completion.json)
retains two unchanged passing controls, one shared sequential capture and their
compact reports. It is a development check, not another performance measurement
or an addition to the 6,747-program sweep population.
