# Beam 1.0 OpenCode pricing

Beam 1.0 Medium in OpenCode averages **$0.02223 per task with complete accounting**
at the frozen 2026-10-30 API comparison rates. The estimate follows the existing
policy of choosing the cheapest live, non-batch OpenRouter endpoint for the
observed token mix: Nebius FP4 at $0.25 input, $0.05 cached input and $1.00 output
per million tokens. The
[pricing snapshot](../../batches/20261025-170121/generation/pricing/pricing-reference.json)
retains all five candidate endpoints and the hash of the
[OpenRouter response](https://openrouter.ai/api/v1/models/reflection/beam-1.0-501b-a23b/endpoints).
Historical profiles retain their frozen rates.

219 of the 220 observations have complete native OpenCode accounting, totaling
$4.86857 at these rates. Cached input is included in input, and reasoning is
included in output. Per-task cost is
`((input - cached) × 0.25 + cached × 0.05 + output × 1.00) / 1,000,000`.
The protocol-terminated attempt retains counters only for its eight completed
requests. Those lower bounds are excluded from complete-task token and cost
averages; the attempt remains included in validation and scoring.

The [request summary](../../batches/20261025-170121/generation/pricing/request-context-summary.json)
covers 3,070 completed requests, including compaction and the partial attempt.
Maximum request input is 30,667 tokens and maximum output is 7,290; reported
cache writes are zero. The selected endpoint has flat context pricing, so no
context-tier split is needed.

Generation used `opencode-go/beam-free` under
[Go's temporary free promotion](https://opencode.ai/v2/docs/console/go/), without
paid fallback. The API-rate estimate is not a subscription bill or measured
quota consumption. The comparison endpoint declares
`reflection/beam-1.0-501b-a23b-20261016` and FP4, whereas the evaluated Go alias is
unversioned. Its serving configuration is not established to be identical to
that comparison endpoint.
