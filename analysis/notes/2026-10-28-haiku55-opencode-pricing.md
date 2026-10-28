# Haiku 5.5 OpenCode pricing

Haiku 5.5 Medium in OpenCode averages **$0.124641 per generated program** at the
frozen 2026-10-28 API comparison rates. All 220 programs have complete native
accounting; their combined estimate is $27.421072. This is not the OpenCode Go
subscription bill or measured quota consumption.

## Request context tiers

The rates match the native Claude Code Haiku comparison in both tiers:

| Input tokens in one request | Input / million | Cached input / million | Output / million |
| --- | ---: | ---: | ---: |
| Up to 100,000 | $0.10 | $0.01 | $0.50 |
| Above 100,000 | $0.50 | $0.05 | $2.50 |

The threshold includes cache reads and writes. A long request uses the higher
rates for its entire input and output; it does not retroactively change earlier
requests. Exactly 100,000 input tokens remains in the lower tier.
[Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing#long-context-pricing)
specifies this rule. Cache creation is priced as ordinary input, consistently
with the other Claude profiles, rather than including cache-write premiums.

Anthropic is tied for the lowest live, non-batch public rates in both tiers.
The [pricing snapshot](../../batches/20261025-170040/generation/pricing/pricing-reference.json)
retains candidate endpoints and the hash of the
[OpenRouter response](https://openrouter.ai/api/v1/models/anthropic/claude-haiku-5.5/endpoints).
Historical profiles retain their frozen rates.

## Exact accounting

The campaign contains 5,749 completed requests, including compaction. Of those,
1,499 requests across 46 programs exceed 100,000 input tokens; the maximum is
309,642. OpenCode's native request counters provide both input and output for
each tier directly. Cached input is a subset of total input, and reasoning is a
subset of output; neither is counted twice.

The [compact per-program records](../../batches/20261025-170040/generation/pricing/context-usage.jsonl)
bind each pair of tier totals to the original source commit and native session
hash. All totals reconcile with the retained generation metadata. The
[request summary](../../batches/20261025-170040/generation/pricing/request-context-summary.json)
pins the accounting method and evidence hashes. Original transcripts remain in
the generated-source repository rather than being duplicated here.

Generation used the Go subscription route `opencode-go/claude-haiku-5-5`, not
the OpenRouter endpoint selected for comparison pricing. The
[Go allowance](https://opencode.ai/v2/docs/console/go/) is a separate accounting
system. Comparisons with Claude Code therefore describe the complete harness
and provider setup, not a pure causal harness effect.
