# Sol 6.1 Medium in OpenCode

This campaign contains 220 independently generated programs across 11 benchmarks,
four backends and five repetitions. It uses the same sequential input, task prompt,
four-hour generation budget and benchmark settings as the native Sol 6.1 comparison.
OpenCode uses its stock build agent and model adapters with isolated configuration,
local shell/build/test access, and no web tools, subagents, MCP or external plugins.
The supported ChatGPT subscription login is used; no API billing is enabled.
Exact versions and effective settings are retained in `generation/`.

## Outcomes

- 219/220 passed the unchanged five-stage scientific validation.
- `matmul_gpt-6.1-sol-oc-medium_mpi_r2` failed the MPI-only parallelization check
  because it also used OpenMP. It remains invalid and was not benchmarked.
- Source-only timing review covered 109 passing MPI/hybrid programs and 20 QT
  implementations across all backends: 119 unique programs after overlap.
- Fourteen programs required timing-only corrections: nine roomsim and five QT.
  All passed independent corrected-source review and scoped native revalidation.
- All 219 eligible programs benchmarked successfully, with one warm-up and five
  measurements each, no retries, and no historical re-execution.
- No new benchmark/backend winner was introduced.

Original code, transcripts and native accounting metadata are retained at
[`352c09d`](https://github.com/PeterTh/llm-eval-generated/tree/352c09d57e14ef93744aa8cc741ff52884079e5f/20261017-192226).
All timing-only edits are in one commit,
[`9012afd`](https://github.com/PeterTh/llm-eval-generated/tree/9012afd8480bb000ff7b01581a91c6b680ef2394/20261017-192226).
The correction registry and benchmark records link both revisions per program.

## Evidence

`validation/records.jsonl` retains exact scientific-validation output and failure
diagnostics. `timing-audit/` retains the general audit, all-backend QT overlay,
independent Luna review and targeted Sol adjudication. `timing-corrections/` retains
accepted edits, source links and revalidation. `benchmark/` retains all measurements,
execution wall times and inherited configuration; `aggregate/` contains the exact
native aggregate. `completion/` retains scoped verification and orchestration evidence.

`generation/observations.jsonl` records exact native token counters, session and
metadata hashes, and retry-excluded elapsed time. The common effective configuration
is stored once and hash-linked from every observation. All 4,021 requests, including
compaction, are accounted for; no request crosses the long-context pricing threshold.
Four provider retries total 9.052 seconds and are excluded from task time. API-only
time is unavailable and remains unset. Two unaccepted infrastructure pilots retain
their incident receipts; none of the 220 accepted observations was repeated.

Programs, transcripts, binaries, build trees, raw review streams and credentials are
not duplicated here. Method layouts refer to exact retained files by content hash.
Root and nested checksum manifests cover the compact artifact.

See the [harness comparison](../../analysis/notes/2026-10-18-sol61-harness-comparison.md),
[pricing note](../../analysis/notes/2026-10-18-sol61-opencode-pricing.md) and
[joint release](../../release/README.md).
