# Haiku 5.5 Medium in Claude Code and OpenCode

## Scope

Each setup contains 220 independent programs: five generations in each of 44
benchmark/backend cells. Sequential input, task prompt, generation budget,
validation and benchmark settings are shared. Stock harness prompts, tools and
agent loops differ, as do the subscription provider routes and campaign dates.
The model aliases are mutable, so this compares complete setups rather than
isolating a causal harness effect.

## Findings

| All-program measure | Claude Code | OpenCode |
| --- | ---: | ---: |
| Passed validation | 219/220 | 219/220 |
| Successfully benchmarked | 219/220 | 217/220 |
| Mean joint score | 7.595 | 7.595 |
| Mean generation time | 807.9 s | 942.7 s |
| Mean total tokens | 1,564,282 | 2,085,509 |
| Mean API-rate cost | $0.090755 | $0.124641 |
| Timing-corrected programs | 33 | 36 |

The mean score is identical, while OpenCode takes 16.7% longer to generate a
program, uses 33.3% more tokens and has a 37.3% higher estimated API-rate cost.
These summaries include all 220 programs, including failures.

OpenCode's extra token consumption is mainly input, including cache reads;
mean output is similar at 49,818 versus 49,163 tokens. Hybrid accounts for much
of the difference: OpenCode averages 5.03 million tokens and 1,807 seconds per
generation there, versus 3.32 million and 1,317 seconds in Claude Code.

OpenCode succeeds in all 55 hybrid benchmarks, versus 54 in Claude Code. Its
three unsuccessful observations are all OpenMP: one roomsim numerical validation
failure, plus QT clustering and roomsim warm-up timeouts at benchmark size.
Those outcomes are retained without retries. No new winner across the complete
model set is introduced; all existing individual winner reviews remain applicable.

## Runtime comparison

For each cell, take the median successful program's five-measurement median.
The table geometrically averages OpenCode/Claude Code ratios with equal weight
per cell; below one favors OpenCode. Both setups have a successful program in
all 44 cells.

| Backend | Runtime ratio | Eligible cells |
| --- | ---: | ---: |
| OpenMP | 1.123 | 11 |
| CUDA | 1.240 | 11 |
| MPI | 0.906 | 11 |
| Hybrid | 0.972 | 11 |
| All | 1.052 | 44 |

OpenCode has lower cell medians in 20 cells and Claude Code in 24. MPI and hybrid
favor OpenCode in aggregate, while OpenMP and CUDA favor Claude Code. Restricting
the calculation to the 41 cells where all ten generated programs successfully
benchmarked gives a similar overall ratio of 1.048.

Individual workloads differ much more than the overall ratio suggests. OpenCode's
N-body MPI median is 2,840 versus 7,623 ms, and matrix multiplication OpenMP is
3,072 versus 7,424 ms. Conversely, Cholesky CUDA is 69 versus 12 ms and SpMV OpenMP
is 2,944 versus 812 ms. These are descriptive distributions of independently
generated implementations, not significance tests or matched-program speedups.

## Accounting and reproduction

Both setups use the same frozen API rates in each request-context tier. Cached
input and reasoning output are counted once, and compaction is included.
OpenCode's recorded 2.017-second provider retry wait is excluded from generation
time. Costs are API-rate comparisons, not subscription bills; the
[pricing evidence](2026-10-28-haiku55-opencode-pricing.md) describes the native
request accounting and the Claude Code mixed-tier output calculation.

Data: the combined 2026-10-28 release, built on artifact commit
`f37be40ad1926244f94cf0c84cda1eb11001cc8b` plus batch `20261025-170040`.
The [context record](../tables/haiku55_harness_context.json) pins the exact scored
input and aggregation rules; the [summary](../tables/haiku55_harness_summary.csv)
and [44-cell table](../tables/haiku55_harness_cells.csv) retain unrounded values.

```bash
python analysis/src/harness_comparison.py --comparison haiku55
```
