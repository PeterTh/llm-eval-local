# Fable 5.1 Medium: cost accounting

Rates are frozen at 2026-11-07 from the retained
[OpenRouter endpoint snapshot](../../batches/20261011-092100/generation/pricing/openrouter-endpoints.json)
and [selection record](../../batches/20261011-092100/generation/pricing/pricing-reference.json):
$10 per million input tokens, $0.25 per million cached-input tokens and $50 per
million output tokens. The Anthropic endpoint ties the three other listed
providers at these non-batch rates, with no request-context tiers. The
[official model page](https://platform.claude.com/docs/en/models/fable-5-1/overview)
provides the model/pricing reference linked from the website.

The 220 accepted native Claude Code observations retain 150,200 uncached-input,
17,050,112 cache-creation, 418,134,763 cache-read and 11,361,929 output tokens.
As for the other Claude profiles, cache creation uses the ordinary input rate:

`((150200 + 17050112) * 10 + 418134763 * 0.25 + 11361929 * 50) / 1000000`

This yields **$844.63326075 total, or $3.8392420943 per observation**. It is an
API-equivalent comparison, not the subscription bill. Existing profiles' rates
and token accounting are unchanged.

The accepted attempts total 325,886.43 generation seconds (24.688 minutes per
observation). Seven historical provider-failed attempts and their waits are
already excluded by the fresh accepted-attempt timers; no further subtraction
is applied. Their unavailable token counters are not imputed. The
[completion audit](../../batches/20261011-092100/generation/completion-audit.json)
and retained retry excerpts distinguish those availability failures from the
220 accepted observations used in the cost and generation-time views.
