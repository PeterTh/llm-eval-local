# Combined release: 2026-10-24

This is a reproducible view over ten retained campaigns, not a second raw-data archive.
`catalog.json` declares the input locations, generated-source revisions and expected counts.
The original campaign remains unchanged in `data/`; the 660 Claude 5 runs remain in
`batches/20260901-162328/`; GPT-6 is under `batches/20260929-135931/`;
Opus 5.5 is under `batches/20261002-142720/`; Sol 6.1 medium and xhigh are under
`batches/20261006-204623/`; Haiku 5.5 is under `batches/20261012-111947/`;
Sonnet 5.5 is under `batches/20261014-212207/`; Sol 6.1 Medium in OpenCode is under
`batches/20261017-192226/`; Luna 6 Medium in OpenCode is under
`batches/20261018-224015/`; DeepSeek V4.1 Flash High in OpenCode is under
`batches/20261019-134042/`. Catalog-declared observation replacements join their
own validation, benchmark and generation evidence by exact run ID; untouched
observations retain their original records and source revisions.

The catalog's
`codex_usage_overlays` joins exact reported counters for all 1,980 GPT-5.6 runs from
`metadata/codex-usage/20260805-120633.jsonl`, preserving the original terminal
counter and session provenance. The GPT-6 and Sol 6.1 native aggregates use the
same exact usage evidence directly; all 1,100 rows are verified against their
recovered counters.
OpenCode's 660 observations retain native request/session counters, including
compaction, and deduplicated effective-configuration records. Usage is complete
for 657 observations; three model-terminated sessions retain explicit lower
bounds and have no full-task cost estimate. Pricing-context
checks bind to the native session exports; provider retry waits are excluded from
generation duration.

This release includes GPT-6 validation, timing review and benchmarks.
The shared correction campaign at `corrections/20261001-gpt6-qt/` applies 81
revalidations and exactly 32 historical QT benchmark replacements. Initial GPT-6
validation observed 611 passes; two confirmed pre-existing defects failed corrected
revalidation and remain invalid, giving 609 eligible programs. Both observations
remain accessible. All 4,435 unrelated historical benchmark records are guarded
unchanged.

The initial Claude 5 generation harness and campaign tooling are published at
[`fa046134`](https://github.com/PeterTh/llm-eval-experiment/tree/fa046134cf22a2cb3b8398567f2cf4115bceb021).
This is a post-campaign source snapshot, not a claim that the runs were launched
from that later commit. The catalog pins the generation script/helper; retained
manifests and the pipeline layout pin the actual evaluation method files by content.

- 7,700 programs, 35 model/effort/harness profiles, 220 programs each.
- 6,785 effectively validated programs and benchmark attempts; 6,380 successful measurements.
- 1,137 timing-fixed programs (including two failed revalidations), with source history.
- 44 benchmark/backend cells, all with reviewed winners; 94 retained reviews total.

DeepSeek V4.1 Flash High in OpenCode contributes 217 validated and successfully
benchmarked programs, including 56 timing-only corrections. Three validation
failures remain in the dataset. Its new CUDA SpMV winner is a practical tie with
the previous Luna result. The [comparison snapshot](../analysis/notes/2026-10-23-deepseek41-opencode-winner-context.json)
pins the preceding release and the unchanged evidence for all 7,480 prior observations.
The [Luna 6](../analysis/notes/2026-10-19-luna6-harness-comparison.md) and
[Sol 6.1 harness comparisons](../analysis/notes/2026-10-18-sol61-harness-comparison.md)
separate all-program outcomes from successful-only runtime comparisons.

`scored_results.csv` is the current analysis and website input. The unchanged historic
log-natural-break threshold procedure is applied to the joint successful-measurement
distribution. `historical_score_changes.csv` records older score changes and distinguishes
joint-threshold changes from affected QT timing-boundary replacements.
The builder also reproduces all 4,620 old scores with the old thresholds as a regression
check. Previous QT observations stay immutable in `data/` and the Claude batch.

`winners.json` retains current winner IDs and comparisons to the original 4,620-run
campaign, five measurements, medians,
ratios, arguments and timing-fix flags. All current winners have individual notes under
`analysis/notes/individual/`; superseded winner notes are retained too. Small median
differences and coarse integer-millisecond timings are identified as practical ties
where appropriate, not treated as statistically established advantages.

Rebuild and check (Ruby standard library only):

```sh
ruby tools/current_release.rb --require-reviews
ruby tools/current_release.rb --check --require-reviews
ruby tools/test_current_release.rb
ruby tools/update_checksums.rb
ruby tools/verify_release.rb
```

`scoring_metadata.yaml` pins the builder, thresholds and retained campaign inputs.
Changes to raw input require an explicit rebuild; website publishing is gated on the
complete artifact verifier as well as the website test suite. See `analysis/README.md`
for regenerating the publication figures and `web/README.md` for a local preview.
