# Terra 6.1 pricing

`gpt-6.1-terra-medium` uses the 2026-10-28 OpenAI Flex rates: $0.50
uncached input, $0.025 cached input and $2.50 output per million tokens.
Flex had the lowest rates among the four live non-batch endpoints in both
request-context bands. The [captured endpoint comparison](../../batches/20261028-200951/generation/pricing/pricing-reference.json)
retains the rates and sources alongside the
[official model pricing](https://developers.openai.com/api/docs/models/gpt-6.1-terra).

Requests above 272,000 input tokens use higher rates for the whole request:
$1 input, $0.05 cached input and $3.75 output per million tokens. All 2,583
requests in the 220 observations contained at most 32,328 input tokens, so
the short-context rates apply throughout. The
[request-level audit](../../batches/20261028-200951/generation/pricing/request-pricing-audit.json)
binds the compact request counters to the recovered native totals.

The [exact usage records](../../metadata/codex-usage/20261028-200951.jsonl)
contain 42,257,780 input tokens, including 38,479,232 cached tokens, and
769,669 output tokens. The 61,000 reasoning tokens are already included in
output; cache-write counters are explicitly zero. Per-run cost is
`((input - cached) × 0.50 + cached × 0.025 + output × 2.50) / 1,000,000`.
This gives $4.7754273 in total, or $0.02170649 per observation. It is an
API-rate comparison, not the Codex subscription bill.
