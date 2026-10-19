# Luna 6 OpenCode pricing

`gpt-6-luna-oc-medium` uses OpenAI Flex rates verified on 2026-10-19:
$0.05 input, $0.005 cached input and $0.25 output per million tokens. These
match the frozen rates used for Luna 6 in Codex. The
[official model page](https://developers.openai.com/api/docs/models/gpt-6-luna)
and [pricing table](https://developers.openai.com/api/docs/pricing) specify
the rates and the 50% Flex discount relative to Standard.

All 220 observations have exact native OpenCode counters, cross-checked
between session records and accounting events. Cached input is included
in input; reasoning is included in output. Cost per observation is
`((input - cached) × 0.05 + cached × 0.005 + output × 0.25) / 1,000,000`.

The [request-context evidence](../../batches/20261018-224015/generation/pricing/request-context-summary.json)
covers 2,864 requests, including compaction. The largest request has 37,207
input tokens, below the 272,000-token surcharge boundary; reported cache
writes are zero. No context-tier estimate is needed for this batch.

These are API-rate estimates, not subscription charges. Storage, tools and
regional premiums are not modeled. Exact counters and source-file digests
are retained with the batch; transcripts remain in the generated-source repository.
