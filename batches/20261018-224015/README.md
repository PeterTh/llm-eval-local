# Luna 6 Medium in OpenCode

This campaign contains 220 independent generations: eleven benchmarks, four
backends and five repetitions. It uses stock OpenCode 1.19.3 with
`openai/gpt-6-luna`, medium effort, the established four-hour task budget and
local build/test tools. Web access, subagents, MCP and external plugins are
disabled. The same sequential input and workload are used by the native Codex
Luna 6 baseline. See the [harness comparison](../../analysis/notes/2026-10-19-luna6-harness-comparison.md).

All 220 generations completed without retries or infrastructure failures.
The four predeclared production preflights are included once. Native counters
record 30,314,520 tokens and 15,462.03 task seconds; API-only time is unavailable.
Shared configuration, per-run accounting, cleanup receipts and request-context
pricing checks are retained under `generation/`. Code and transcripts remain
in the generated-source repository.

## Validation and timing

181 programs passed all five native validation stages; 39 ordinary failures
remain in the dataset. Timing review covered 85 successful MPI/hybrid programs
and 12 successful QT implementations across backends, or 90 unique programs.
Luna performed the source-only reviews; Sol 6.1 adjudicated uncertainty or
disagreement. The [resolved selection](timing-audit/resolved-selection.json)
contains 51 valid timings, 39 requiring correction and no unresolved cases.

All 39 timing-only corrections compiled, received independent acceptance and
passed native revalidation. One insufficient Cholesky proposal was revised;
the other 38 accepted proposals and reviews were reused unchanged. Earlier
proposals and decisions remain in the [revision evidence](completion/correction-revision-1.json).
Both original and corrected Git revisions are retained in the
[correction registry and report](timing-corrections/README.md).

## Measurements

All 181 eligible programs were benchmarked using the historical sizes,
iterations, timeouts and resource profiles: one warm-up and five measurements.
The four backend canaries were reused without re-execution. There were no
retries, recalibration or historical reruns.

| Backend | Validated / 55 | Successful benchmarks |
| --- | ---: | ---: |
| OpenMP | 52 | 44 |
| CUDA | 44 | 41 |
| MPI | 49 | 41 |
| Hybrid | 36 | 23 |
| Total | 181 / 220 | 149 |

The 32 benchmark failures comprise 30 warm-up timeouts, one program requiring
a square MPI process count, and one program crash. Their exact diagnostics
are retained. This batch introduces no new cell winners; the combined release
preserves all 7,260 prior observations and applies the unchanged joint scoring
procedure. The [completion report](completion/benchmark-completion-review.json)
and [winner comparison](../../analysis/notes/2026-10-19-luna6-opencode-winner-context.json)
bind the measurements and preservation checks.

## Retained evidence

`validation/records.jsonl` retains each result's metadata, staging provenance,
exact execution output, commands, exit statuses, wall times, and source-log
hashes. Successful compiler output is omitted; failure diagnostics remain.
`timing-audit/` retains inventories, exclusions, source-grounded findings,
independent reviews, adjudications, and compact attempt provenance.
Original generated code, transcripts, binaries and build trees are not copied.

Every artifact is covered by `checksums.sha256`. Exact method files are under
`method/`; `method/layout.json` maps their stored paths to the experiment-repo
paths needed to reconstruct a runnable checkout. This avoids modifying frozen
code merely to accommodate the artifact repository's flat snapshot layout.

