# Luna 6 Medium: Codex versus OpenCode

## Scope

Each profile contains 220 independent programs: five generations for each of
44 benchmark/backend cells. Sequential input, task prompt, generation budget,
validation and measurement settings are shared; stock harness prompts, tools and
agent loops differ. Campaigns ran on different dates using provider model aliases.
This is a descriptive comparison of complete setups, not an isolated causal
harness effect.

## Findings

| All-program measure | Codex | OpenCode |
| --- | ---: | ---: |
| Passed validation | 171/220 | 181/220 |
| Successfully benchmarked | 150/220 | 149/220 |
| Mean joint score | 5.836 | 5.986 |
| Mean generation time | 100.4 s | 70.3 s |
| Mean total tokens | 152,423 | 137,793 |
| Mean API-rate cost | $0.002580 | $0.002680 |
| Timing-corrected programs | 18 | 39 |

OpenCode finishes generation 30.0% faster and uses 9.6% fewer tokens. Its ten
additional validation passes do not translate into more completed benchmarks:
32 validated programs fail at the benchmark configuration, versus 21 in Codex.
OpenCode improves validation and benchmark coverage in OpenMP and hybrid, while
CUDA and MPI have fewer successful benchmarks. All failures remain in the score,
generation-time and cost summaries.

Fewer tokens do not mean lower estimated cost here. OpenCode averages 25,376
uncached input tokens versus 20,997 in Codex; its lower cached-input volume and
slightly lower output volume do not offset that difference. At identical frozen
rates, the estimate is 3.9% higher. These are API-rate estimates, not subscription
charges.

## Runtime comparison

Take each successful program's five-measurement median, then the median successful
program in each cell. The table geometrically averages the OpenCode/Codex ratios
with equal weight per eligible cell; below one favors OpenCode. Only cells with
at least one successful program in both harnesses are included.

| Backend | Runtime ratio | Eligible cells / 11 |
| --- | ---: | ---: |
| OpenMP | 0.998 | 10 |
| CUDA | 1.004 | 9 |
| MPI | 1.046 | 11 |
| Hybrid | 1.849 | 6 |
| All | 1.124 | 36 / 44 |

OpenCode has lower cell medians in 15 of the 36 comparable cells; Codex has lower
medians in 21. OpenMP and CUDA are nearly equal in aggregate. The six comparable
hybrid cells all favor Codex, but their successful-program counts are small and
unequal. OpenCode also succeeds in Floyd–Warshall hybrid, where Codex has no
successful program; conversely, only Codex succeeds in QT CUDA and hybrid.

Differences vary considerably by workload. Black–Scholes MPI is 62.459 versus
12.516 ms, while Cahn–Hilliard CUDA is 4,267 versus 8,510 ms and SpMV OpenMP is
3,167 versus 4,835 ms. These are descriptive cell medians, not significance tests.
Restricting the comparison to the 13 cells where all ten generated programs
successfully benchmarked gives a runtime ratio of 1.050. That subset excludes
most hybrid cells and should not be read as a full-workload result.

No new winner across the complete model set was introduced. Existing individual
winner reviews remain applicable.

## Accounting and reproduction

Costs use exact native counters and common frozen Flex rates. Cached input and
reasoning output are counted once; compaction is included. Generation duration
excludes recorded provider retry waits; this OpenCode campaign had none. See the
[pricing evidence](2026-10-19-luna6-opencode-pricing.md).

Data: the combined 2026-10-19 release, built on artifact commit
`8beae1d8eaa403d7eaaef7f2d439c6e05e53731f` plus batch `20261018-224015`.
The [context record](../tables/luna6_harness_context.json) pins the scored input
and aggregation rules; the [summary](../tables/luna6_harness_summary.csv) and
[44-cell table](../tables/luna6_harness_cells.csv) retain unrounded values.
The [Sol 6.1 comparison](2026-10-18-sol61-harness-comparison.md) uses the same method.

```bash
python analysis/src/harness_comparison.py --comparison luna6
```
