# Claude 5 pricing profiles

Observed 2026-09-29. These are reproducible API-cost estimates, not the subscription
cost paid for generation. Historical model profiles retain their 2026-08-22 prices;
adding this batch does not silently reprice them.

| Model | Input / million | Cache read / million | Output / million |
| --- | ---: | ---: | ---: |
| Fable 5 | $10 | $1 | $50 |
| Opus 5 | $5 | $0.50 | $25 |
| Sonnet 5 | $2 | $0.20 | $10 |

Sources: the public OpenRouter [Fable 5 endpoint listing](https://openrouter.ai/api/v1/models/anthropic/claude-5-fable-20260609/endpoints),
[Opus 5 endpoint listing](https://openrouter.ai/api/v1/models/anthropic/claude-opus-5/endpoints),
and [Sonnet 5 endpoint listing](https://openrouter.ai/api/v1/models/anthropic/claude-sonnet-5/endpoints).
The corresponding human-readable pages are [Fable](https://openrouter.ai/anthropic/claude-fable-5),
[Opus](https://openrouter.ai/anthropic/claude-opus-5), and [Sonnet](https://openrouter.ai/anthropic/claude-sonnet-5).
The standard Anthropic endpoint ties the least-expensive listed non-batch rates
in all three token categories for each model, so the choice does not depend on
the observed token mix. Other standard global providers list the same rates;
regional premiums and the Opus fast endpoint are more expensive. Batch variants
are excluded, consistently with the established analysis. Fable 5.1 is not substituted
for the evaluated Fable 5.

The existing cost convention is unchanged: input includes cached-read tokens;
cache reads are subtracted before pricing uncached input. Cache-creation tokens
remain in uncached input and are priced at the standard input rate, not the
provider's cache-write premium. Consequently this is not an exact billing estimate.
The retained generation-metadata correction record explains the cumulative token
accounting and subtraction of server retry waits from generation times.
