# Terra 6.1 pricing

Terra 6.1 Medium, XHigh and Ultra use the same frozen 2026-10-28 OpenAI Flex rates: $0.50
uncached input, $0.025 cached input and $2.50 output per million tokens.
Flex had the lowest rates among the four live non-batch endpoints in both
request-context bands. The [captured endpoint comparison](../../batches/20261028-200951/generation/pricing/pricing-reference.json)
retains the rates and sources alongside the
[official model pricing](https://developers.openai.com/api/docs/models/gpt-6.1-terra).

Requests above 272,000 input tokens use higher rates for the whole request:
$1 input, $0.05 cached input and $3.75 output per million tokens. All requests
recorded in the three 220-observation campaigns are below this threshold. Each request-level
audit binds compact request counters to the recovered native totals.

| Effort / request audit | Requests | Maximum input per request | Total API-equivalent cost | Mean per observation |
| --- | ---: | ---: | ---: | ---: |
| [Medium](../../batches/20261028-200951/generation/pricing/request-pricing-audit.json) | 2,583 | 32,328 | $4.7754273 | $0.02170649 |
| [XHigh](../../batches/20261102-030935/generation/pricing/request-pricing-audit.json) | 4,382 | 46,796 | $9.1368516 | $0.04153114 |
| [Ultra](../../batches/20261105-131145/generation/pricing/request-pricing-audit.json) | 18,126 | 51,899 | ≥$26.8149000 | ≥$0.12188591 |

The exact usage records for [Medium](../../metadata/codex-usage/20261028-200951.jsonl)
and [XHigh](../../metadata/codex-usage/20261102-030935.jsonl) retain input, cached
input, output and reasoning counts. Cached input is already included in input,
and reasoning in output; cache-write counters are explicitly zero. Per-run cost is
`((input - cached) × 0.50 + cached × 0.025 + output × 2.50) / 1,000,000`.
This is an API-rate comparison, not the Codex subscription bill.

[Ultra's usage records](../../metadata/codex-usage/20261105-131145.jsonl) sum unique
recorded requests across 220 parent and 645 child sessions. All parent tasks
completed, but 49 observations include interrupted requests with uncertain final
usage. The recorded counters are preserved and their costs are lower bounds;
unknown usage is not replaced with zero. The 171 observations without this flag
use the complete recorded native counters. Reasoning remains a subset of output.
