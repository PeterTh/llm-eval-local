# DeepSeek V4.1 Flash High in OpenCode

The current release includes 220 programs, 217 validation passes and successful
benchmarks, and 56 timing-fixed implementations. All measurements use the
established benchmark sizes, resources, one warmup and five measured executions.
Three validation failures remain in the dataset.

The [release catalog](../../release/catalog.json) defines the exact current view:
196 observations use this directory's native evidence; 24 use the independently
validated [scoped evidence set](replacements/20261024-isolated/).
Each set retains its own immutable source revisions and configuration digests.
Do not concatenate the two sets or use the archived native summary as the
current campaign total.

## Retained evidence

- `validation/` contains scientific outcomes, exact output and failure diagnostics.
- `timing-audit/` contains Luna-first static reviews and selected Sol adjudications.
- `timing-corrections/` contains timing-only patches, independent reviews and revalidation.
- `benchmark/` contains native measurements, execution status and configuration.
- `generation/` contains compact request accounting, harness configuration and provenance.
- `replacements/20261024-isolated/` uses the same layout for its scoped observations.

Original and timing-corrected program sources and transcripts remain in the
generated-source Git repository. Per-run website links select the applicable
revisions; binaries and build trees are not duplicated here.

Usage accounting is complete for 217 observations. Three model-terminated
sessions retain completed-request lower bounds, with full-task token and cost
fields unavailable. They remain included in scientific validation and scoring.
The [pricing note](../../analysis/notes/2026-10-23-deepseek41-opencode-pricing.md)
describes the dated API-rate comparison, separate from subscription billing.

All current cell winners have individual reviews; the new
[CUDA SpMV winner](../../analysis/notes/individual/spmv_deepseek-v4.1-flash-oc-high_cuda_r2.md)
is a practical tie with the previous Luna result.

Checksums cover the compact evidence, and method layouts bind the exact frozen
pipeline files. Rebuild the current view with `ruby tools/current_release.rb`
from the repository root.
