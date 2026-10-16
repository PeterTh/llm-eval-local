# Sonnet 5.5 pricing

Sonnet 5.5 Medium uses rates frozen on 2026-10-15: **$2 input, $0.10 cache read,
and $10 output per million tokens**, without request-context price tiers.
Anthropic ties the lowest live non-batch endpoint rates in the
[retained endpoint snapshot](../../batches/20261014-212207/generation/pricing/openrouter-endpoints.json).
The [official model page](https://platform.claude.com/docs/en/models/sonnet-5-5/overview)
confirms these rates.

The cost comparison prices the retained native cumulative token counts, counting
cache creation at the ordinary input rate as for the other Claude profiles. It
is a normalized API-cost comparison, not the Claude subscription bill. See the
[pricing record](../../batches/20261014-212207/generation/pricing/pricing-reference.json)
for the selected endpoint and source hashes.
