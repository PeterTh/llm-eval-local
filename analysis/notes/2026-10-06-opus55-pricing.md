# Opus 5.5 pricing

The `claude-opus-5.5-cc-medium` profile uses the 2026-10-06 non-batch
Anthropic endpoint prices: **$4 input, $0.20 cached input, and $20 output per
million tokens**. These rates are reported by the
[OpenRouter endpoint catalog](https://openrouter.ai/api/v1/models/anthropic/claude-opus-5.5/endpoints)
and [Anthropic's pricing documentation](https://platform.claude.com/docs/en/about-claude/pricing).
They are componentwise no higher than the other listed non-batch endpoints;
Anthropic is the selected provider. Existing model profiles keep their dated rates.

All 220 generation runs have exact reported input, cache-read, cache-creation and
output counters, retained in the batch's `generation/observations.jsonl` and
verified against its native aggregate. The inclusive input count contains cache
reads and writes. Cost is `(input - cached) × 4 + cached × 0.20 + output × 20`,
divided by one million, computed per run and then averaged.

As for the other Claude profiles, cache creation is priced as ordinary input;
cache-write surcharges, tools, regional premiums, fast mode and batch discounts
are not modeled. Reasoning tokens are already part of output, not an extra charge.
This is a consistent API-rate comparison, not the Claude Code subscription bill
or the harness's reported dollar total.

The reproducible profile is in `analysis/src/all_models_score_vs_cost.py`; its
dated rates, source URLs and measured token averages are exported to
`analysis/tables/4d_all_models_score_vs_cost.csv` and consumed by the website.
