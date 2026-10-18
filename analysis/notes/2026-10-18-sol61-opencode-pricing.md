# Sol 6.1 OpenCode pricing

`gpt-6.1-sol-oc-medium` uses OpenAI Flex rates verified on 2026-10-18:
$1 input, $0.05 cached input and $5 output per million tokens. These match
the frozen rates used for Sol 6.1 in Codex. The
[official model page](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
and [pricing table](https://developers.openai.com/api/docs/pricing) establish
the rates and the 50% Flex discount relative to Standard.

All 220 observations have exact native OpenCode counters, independently
cross-checked between session records and accounting events. Cached input
is included in input; reasoning is included in output. Cost per observation is
`((input - cached) × 1 + cached × 0.05 + output × 5) / 1,000,000`.

The retained [request-context evidence](../../batches/20261017-192226/generation/pricing/request-context-summary.json)
covers 4,021 requests, including compaction. The largest request has 63,446
input tokens, below the 272,000-token surcharge boundary; reported cache
writes are zero. No context-tier estimate is needed for this batch.

This is an API-rate comparison, not the ChatGPT subscription bill. Storage,
tools and regional premiums are not modeled. Exact counters and source-file
digests are retained with the batch; transcripts are not duplicated here.
