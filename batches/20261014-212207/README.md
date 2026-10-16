# Sonnet 5.5 Medium

This campaign contains 220 programs: 11 benchmarks, four backends and five
repetitions, generated with Sonnet 5.5 at explicit medium effort through the shared
Claude Code harness. **215 programs passed validation and all 215 completed
benchmarking successfully.** Results are included in the jointly scored
[combined release](../../release/README.md).

## Validation and timing

The five native validation failures are retained without retries: N-body MPI r1
and r5 mix MPI with OpenMP and fail the established backend check; room simulation
hybrid r1–r3 fail numerical output comparison.

Static timing review covers 105 passing MPI/hybrid programs and all 20 passing
QT-clustering programs, or 115 unique implementations. The
[resolved decisions](timing-audit/resolved-selection.json) identify 44 valid timers
and 71 timing-only corrections. All 71 corrections passed compilation,
independent post-fix review and scoped native revalidation. The
[correction registry and report](timing-corrections/README.md) retain the findings.

The source repository retains both revisions:

- [Original generated programs](https://github.com/PeterTh/llm-eval-generated/tree/8fe249fe2622f21b32faf8d13cd290ce902f78cd/20261014-212207)
- [Timing-corrected programs](https://github.com/PeterTh/llm-eval-generated/tree/6196b2ba8d2509ff0a7ba87d17d846a479a39282/20261014-212207)

Benchmark records carry the timing-fix flag and per-program source links.
All 44 workload configurations, resource profiles and timeouts are inherited
unchanged. Each program has one warm-up and five measurements. Four initial
checks are reused in the 215 results; no completed case or historical benchmark
was repeated. See the [completion checks](completion/benchmark-completion-review.json).

Sonnet 5.5 introduces no new cell winners. The
[comparison snapshot](../../analysis/notes/2026-10-16-sonnet55-winner-context.json)
preserves all 6,820 prior observations; 114 prior scores change solely through
joint thresholds. All 44 current winners already have individual reviews.

## Generation and pricing

The retained generation observations contain 47,058,346 native reported tokens
and 46,457.999 seconds, averaging 3.52 minutes per task, with no provider retries.
One QT OpenMP observation uses a user-approved, explicitly labeled native duration
of 865.229 seconds because its wrapper measurement is unavailable. That duration
excludes wrapper setup and teardown; the wrapper exit status remains unknown.
Its [recovery evidence](generation/recoveries/qtclustering_claude-sonnet-5.5-cc-medium_omp_r2.json)
binds the original source and metadata, and the qualifier is preserved in the
release and website. The original agent completed the program; it was not regenerated.

[Pricing](../../analysis/notes/2026-10-15-sonnet55-pricing.md) is frozen on
2026-10-15 at $2 input, $0.10 cache read and $10 output per million tokens,
without request-context tiers. Cache creation uses the ordinary input rate under
the shared API-cost comparison convention.

## Retained evidence

`validation/` contains all initial outcomes and exact execution output;
`timing-audit/` contains compact static reviews and resolved decisions;
`timing-corrections/` contains the correction registry and revalidation;
`benchmark/` contains measured samples, wall times and provenance. `aggregate/`
provides the normalized 220-program input to combined scoring, and `generation/`
retains accounting, recovery and pricing evidence.

Method layouts refer to existing identical snapshots where possible. Checksums
cover the retained artifacts. Generated programs and transcripts remain in their
source repository; binaries, build trees and repeated successful benchmark logs
are not copied here.

