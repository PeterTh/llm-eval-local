# Haiku 5.5 request-context pricing

The Haiku 5.5 Medium profile uses rates frozen on 2026-10-14. Anthropic was tied
for the lowest live non-batch rates in both context tiers. The threshold applies
to each request's input length, including cache reads and writes, not to the
cumulative token count of a generation session. Exactly 100,000 input tokens use
the short tier. See the [official model pricing](https://platform.claude.com/docs/en/models/haiku-5-5/overview)
and [long-context definition](https://platform.claude.com/docs/en/about-claude/pricing#long-context-pricing).

| Input tokens per request | Input / million | Cache read / million | Output / million |
| --- | ---: | ---: | ---: |
| Up to 100,000 | $0.10 | $0.01 | $0.50 |
| Over 100,000 | $0.50 | $0.05 | $2.50 |

The comparison prices cache creation as ordinary input, consistently with the
other Claude profiles. It is an API-rate estimate, not a subscription bill.

## Evidence and recovery

[Compact context usage](../../batches/20261012-111947/generation/context-usage/usage.jsonl)
retains 220 observations covering 4,747 requests. Of these, 1,034 requests in
50 observations exceed the threshold. Request input and cache-lifetime counts
reconcile exactly with native cumulative totals and original Git-pinned transcripts.
The [recovery receipt](../../batches/20261012-111947/generation/context-usage/recovery.json)
and method layout identify the parser and all retained hashes. The
[endpoint snapshot](../../batches/20261012-111947/generation/context-usage/openrouter-endpoints.json)
supports provider selection.

Streamed per-request output counters are incomplete lower bounds. For the 170
single-tier observations, the native final output total determines the tier total
directly. For the 50 mixed-tier observations, subtracting reported input/cache
charges from the native list-price total leaves the output charge. Together with
the native total output count and the two documented output rates, this uniquely
determines the two aggregate output counts. Every split is an integer, lies within
the native total, and satisfies the streamed lower bounds. These splits are labeled
as **derived**, not directly reported per-request measurements.

The retained native list-price total is $22.65306548. Removing $2.68697680 of
cache-write premiums yields the comparison total of $19.96608868, about $0.090755
per task. Original aggregate token counters are unchanged. Python analysis and the
website independently recompute costs from the retained bands, rejecting missing
evidence or mismatched tokens, source revisions, thresholds, or provenance labels.

Rebuild the cost table and figure with:

```bash
python analysis/src/all_models_score_vs_cost.py
```
