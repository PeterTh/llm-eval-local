# Supplemental correctness validation

## Release effect

The completed Floyd–Warshall, stencil-interior and shape/topology checks exclude
175 previously validated programs: 142 had successful performance measurements,
and 33 had already failed benchmarking. All receive the existing failed-external-
validation category and score 4. The release now has 7,440 validation passes and
7,032 eligible successful measurements across 8,580 programs.

All 44 current winners remain eligible. No generated or sequential source was
changed, and no performance benchmark was rerun. Original validation records and
timings remain available; only derived eligibility and scoring change. The same
joint threshold procedure changes another 49 scores without changing their timings.

The [release impact record](2026-11-04-validation-strengthening-impact.json)
lists all newly excluded IDs, prior scores and measurement eligibility,
validation cases, reasons and evidence links. It includes the 49 joint rescoring
changes and model counts. The baseline is release
`c75207d5608801d820eceffe4ffeae6576e4be51`. Eight earlier Unstructured
exclusions remain in effect, giving 183 supplemental exclusions in total.

| Benchmark | Newly failed | Previously successful measurements |
| --- | ---: | ---: |
| Roomsim | 61 | 59 |
| N-body | 46 | 45 |
| Cholesky | 19 | 7 |
| Floyd–Warshall | 15 | 14 |
| Unstructured | 14 | 3 |
| Matrix multiplication | 7 | 6 |
| Black–Scholes | 3 | 2 |
| QT clustering | 3 | 1 |
| Stencil | 3 | 1 |
| SpMV | 2 | 2 |
| Cahn–Hilliard | 2 | 2 |

## Completed checks

The [winner audit](2026-11-03-winner-validity-audit.md) identified coverage gaps.
Retrospective checks then covered all applicable programs still passing external
validation, including those whose subsequent benchmark failed.

- **Floyd integer matrix:** 708 checks, 705 passes and three failures. Source-matched
  archived output supplied 626 checks; 82 required correctness executions.
  Integer-result hashes expose matrix errors missed by sparse printed samples.
  The three mismatches were individually investigated; floating-point hashes
  do not determine validation outcomes.
- **Stencil interior:** 699 checks, 697 passes and two failures. A 65×61×67 grid
  and 21 iterations place printed samples inside the grid and test remainder
  and odd-iteration handling against the unchanged sequential reference.
- **Shape and topology:** 8,176 checks across 7,610 programs, with 8,006 passes,
  170 distinct failures and no skipped checks. All 25 cases are represented.
  Non-divisible dimensions and benchmark resource profiles exercise partition
  boundaries, partial tiles and rank/thread-dependent paths; selected larger
  OpenMP cases cover size-dependent implementations. The two pilot failures
  are included in the 170, not counted again.

Individual reviews distinguish numerical defects, invalid memory/partition
handling, races, output failures and timeouts. Six exclusive OpenMP timeouts are
execution failures under the unchanged 30-second validation limit, not demonstrated
numerical errors. All six already lacked a successful benchmark.

## Scheduling and provenance

The bounded-concurrency pilot found roughly 13.5% higher MPI throughput with two
workers. The sweep used two workers for nine MPI strata and one elsewhere, with
unchanged resource allocations, affinity, timeouts and comparisons. Four-worker
scheduling-pilot timeouts are not scientific exclusions. Concurrency guards received
individual resolutions before continuation; retained reviews distinguish program
defects from scheduling effects. Scientific failures were not retried into passes.

Exports bind effective source revisions, build receipts, executed binaries,
unchanged sequential references and results. The full shape receipt also binds
the approved plan, concurrency policy, attempt methods, completion and reviews.
Builds and runtime workspaces stayed under local `/tmp`; compact persistent
evidence contains no binaries or copied programs.

- [Floyd evidence](../../validation-supplements/20261103-floyd-integer-hash/export.json)
- [Stencil evidence](../../validation-supplements/20261103-stencil-interior/export.json)
- [Shape pilot](../../validation-supplements/20261103-shape-topology-pilot/export.json)
- [Complete shape sweep](../../validation-supplements/20261103-shape-topology-full/export.json)
- [Individual shape findings](../../validation-supplements/20261103-shape-topology-full/shape-full-reviews/)

The full shape export retains 102,490,184 bytes excluding its master receipt;
Floyd and stencil retain 4,229,011 and 8,639,934 bytes excluding their receipts.
The release verifies files and reproduces comparisons without executing evaluated
programs. Future native validation uses the same approved cases and policy.

## Remaining coverage

The [SpMV work-count pilot](2026-11-04-spmv-work-count-pilot/review.json) inspected
12 programs using source and compiled code. It found no omitted work in that
sample; the other 710 eligible SpMV programs have not received that review.
This is not an automatic work-count validator. Tolerant full-array comparison
remains a separate follow-up; floating-point checks still use printed numerical
summaries and samples.

With full Git history, reproduce this release's impact record using
`ruby analysis/src/validation_strengthening_impact.rb`. Rebuild eligibility
and scores with `ruby tools/current_release.rb --require-reviews`, then regenerate
the [current analyses](../README.md), checksums and website. Historical campaign
records and individual-review snapshots remain unchanged.
