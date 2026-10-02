# GPT-6 pricing snapshot

The three new profiles use the lowest published non-batch OpenAI processing tier,
Flex, frozen on 2026-10-02. Flex eligibility follows the existing cost comparison's
non-batch policy. These profiles cite official model documentation directly rather
than claiming a new OpenRouter endpoint comparison. Historical profiles, rates and
endpoint choices are unchanged.

USD per million tokens, uncached input / cached input / output:

- [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol): 1 / 0.1 / 5.
- [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna): 0.05 / 0.005 / 0.25.
- [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra): 5 / 0.5 / 25.

Each cited model page gives Standard rates and states that Flex costs half as much.
The Sol profile is for GPT-6 Sol, not GPT-6.1 Sol. Exact final cumulative session
counters are available for all 660 generated programs. Cached tokens are included
in input; reasoning tokens are included in output. Neither is counted twice.

As for the existing comparison, these are short-context API-rate estimates, not
subscription invoices. Long-context premiums, separate cache-write premiums,
regional uplifts, tool charges and availability delays are not modeled. Missing
cache-write counters are not treated as proof of zero cache writes.
