# Combined release: 2026-10-06

This is a reproducible view over four retained campaigns, not a second raw-data archive.
`catalog.json` declares the input locations, generated-source revisions and expected counts.
The original campaign remains unchanged in `data/`; the 660 Claude 5 runs remain in
`batches/20260901-162328/`; GPT-6 is under `batches/20260929-135931/`;
Opus 5.5 is under `batches/20261002-142720/`.

The catalog's
`codex_usage_overlays` joins exact reported counters for all 1,980 GPT-5.6 runs from
`metadata/codex-usage/20260805-120633.jsonl`, preserving the original terminal
counter and session provenance. GPT-6's native aggregate uses the same exact usage
evidence directly; all 660 rows are verified against their recovered counters.

This release includes GPT-6 validation, timing review and benchmarks.
The shared correction campaign at `corrections/20261001-gpt6-qt/` applies 81
revalidations and exactly 32 historical QT benchmark replacements. Initial GPT-6
validation observed 611 passes; two confirmed pre-existing defects failed corrected
revalidation and remain invalid, giving 609 eligible programs. Both observations
remain accessible. All 4,435 unrelated historical benchmark records are guarded
unchanged. No new measurement executions were performed during integration.

The Claude generation harness and campaign tooling are published at
[`fa046134`](https://github.com/PeterTh/llm-eval-experiment/tree/fa046134cf22a2cb3b8398567f2cf4115bceb021).
This is a post-campaign source snapshot, not a claim that the runs were launched
from that later commit. The catalog pins the generation script/helper; retained
manifests and the pipeline layout pin the actual evaluation method files by content.

- 6,160 programs, 28 model/effort combinations, 220 programs each.
- 5,295 effectively validated programs and benchmark attempts; 4,922 successful measurements.
- 913 timing-fixed programs (including two failed revalidations), with source history.
- 44 benchmark/backend cells; 13 newly reviewed Opus 5.5 winners, 86 retained reviews total.

Opus 5.5 adds 219 successful benchmarks and preserves its one validation failure.
Its 83 timing-only corrections passed revalidation before measurement. All 5,940
prior observations are unchanged; 263 prior scores change through joint thresholds.
The [Opus 5.5 review context](../analysis/notes/2026-10-06-opus55-winner-context.json)
pins the previous release at `c31465b`, source revisions and comparison vectors.

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
