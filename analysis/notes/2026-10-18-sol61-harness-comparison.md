# Sol 6.1 Medium: Codex versus OpenCode

## Scope

The two profiles each contain 220 independent programs: five generations for each
of 44 benchmark/backend cells. They share sequential input, task prompt, generation
budget, validation and measurement settings. Their stock harness prompts, tools and
agent loops differ. Campaigns ran at different dates and use provider model aliases,
so this compares complete setups, not a separately identified causal harness effect.

## Findings

| All-program measure | Codex | OpenCode |
| --- | ---: | ---: |
| Validated and successfully benchmarked | 219/220 | 219/220 |
| Mean joint score | 8.109 | 8.014 |
| Mean generation time | 5.16 min | 5.75 min |
| Mean total tokens | 491,436 | 310,757 |
| Mean API-rate cost | $0.1092 | $0.0914 |
| Timing-corrected programs | 9 | 14 |

OpenCode uses 36.8% fewer tokens and has a 16.3% lower token-based cost estimate,
but takes 11.4% longer on average. The difference in token volume is principally
input, especially cached input, rather than output: mean output is 9,446 versus
8,822 tokens. Equal validation success does not imply identical generated programs
or performance. Neither profile's ordinary validation failure is removed from the
score, time or cost summaries.

For runtime, first take the median of each successful program's five measurements,
then the median successful program in each cell. The table below geometrically
averages the OpenCode/Codex ratios with equal weight per cell; below one favors
OpenCode.

| Backend | Runtime ratio | Cells |
| --- | ---: | ---: |
| OpenMP | 1.019 | 11 |
| CUDA | 1.501 | 11 |
| MPI | 1.198 | 11 |
| Hybrid | 0.940 | 11 |
| All | 1.146 | 44 |

This is not a uniform slowdown: 20 cell medians favor OpenCode, 22 favor Codex and
two are equal. Many are close. Larger gaps include CUDA QT (889 versus 86 ms) and
MPI unstructured (4,647.934 versus 1,241.536 ms), while OpenCode's QT hybrid and MPI
medians are lower (26 versus 64 ms and 9 versus 19 ms). These descriptive differences
are not significance tests. Restricting to the 43 cells where all ten programs
successfully benchmarked gives an overall ratio of 1.135; the only excluded cell
is matmul/MPI, where each harness has one validation failure.

No new winner across the complete model set was introduced. Existing individual
winner reviews therefore remain applicable.

## Accounting and reproduction

Costs use the same frozen Flex rates and exact native counters, with cached input
and reasoning output counted once. They are API-rate estimates, not subscription
charges. Generation time excludes recorded provider retry waits. OpenCode has no
separate API-only duration. See the [pricing evidence](2026-10-18-sol61-opencode-pricing.md).

Data: the combined 2026-10-18 release, built on artifact commit
`659b18e1be23fb0caea978082731104b205f46d3` plus batch `20261017-192226`.
The [context record](../tables/sol61_harness_context.json) pins the scored CSV,
source batches and aggregation rules; the [summary](../tables/sol61_harness_summary.csv)
and [44-cell table](../tables/sol61_harness_cells.csv) retain unrounded results.

```bash
python analysis/src/sol61_harness_comparison.py
```
