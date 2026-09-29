# Combined release: 2026-09-29

This is a reproducible view over two retained campaigns, not a second raw-data archive.
`catalog.json` declares the input locations, generated-source revisions and expected counts.
The original campaign remains unchanged in `data/`; the 660 Claude 5 runs remain in
`batches/20260901-162328/`.

The Claude generation harness and campaign tooling are published at
[`fa046134`](https://github.com/PeterTh/llm-eval-experiment/tree/fa046134cf22a2cb3b8398567f2cf4115bceb021).
This is a post-campaign source snapshot, not a claim that the runs were launched
from that later commit. The catalog pins the generation script/helper; retained
manifests and the pipeline layout pin the actual evaluation method files by content.

- 5,280 programs, 24 model/effort combinations, 220 programs each.
- 4,467 fully validated programs and benchmark attempts; 4,115 successful measurements.
- 761 timing-only corrected programs, with original and corrected Git source links.
- 44 benchmark/backend cells; 24 new minimum-median winners (23 Opus 5, one Fable 5).

`scored_results.csv` is the current analysis and website input. The unchanged historic
log-natural-break threshold procedure is applied to the joint successful-measurement
distribution. `historical_score_changes.csv` records the 640 older scores changed solely
by those thresholds/new fastest results; their measured values are unchanged.
The builder also reproduces all 4,620 old scores with the old thresholds as a regression
check. No performance measurements were rerun for this integration.

`winners.json` retains all current/previous winner IDs, five measurements, medians,
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
