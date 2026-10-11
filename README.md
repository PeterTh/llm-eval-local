# LLM Autoparallelization Benchmark Data Repository

This repository contains extended validation, performance benchmarking, scoring,
and analysis artifacts for LLM-based parallelization, using the methodology first
introduced in the paper [**Evaluating the Parallelization Capabilities of
State-of-the-art Agentic Large Language Models**](https://doi.org/10.1007/978-3-032-35248-4_2)
presented at Euro-Par 2026.

It serves as the basis for (and contains the source of) the website

>  **https://peterth.github.io/llm-eval-local**

which enables convenient visualization, filtering and browsing of this dataset.

----

The LLM-generated programs are intentionally not duplicated here. They are retained
in [`llm-eval-generated`](https://github.com/PeterTh/llm-eval-generated) and are joined
to these records by run ID, source batch, repository commit, and staged-content
SHA-256 digest.

## What is retained

- immutable provenance, environment, preflight, calibration, and amendment records;
- all 6,600 initial validation outcomes and scoped revalidations, including exact execution output;
- all 5,734 current benchmark outcomes (5,361 successful), measured values and wall times;
- raw diagnostic logs for failures, sequential references, and amended attempts;
- static MPI/hybrid timing audits covering 2,562 programs, all-backend QT audits
  of 485 validated programs, 924 timing-fixed implementations, and scoped rerun comparisons;
- aggregate datasets, scoring inputs, audit records, and final scores;
- compact, provenance-bound Codex usage records for 1,980 GPT-5.6, 660 GPT-6 and 440 GPT-6.1 runs;
- the exact final local-evaluation pipeline source snapshot; and
- reproducible analysis source and final publication tables/figures as they are added.

Build directories, binaries, compiler intermediates, copied program sources, repeated
successful build logs, and repeated successful benchmark stdout are excluded. See
[RETENTION.md](RETENTION.md) for the complete policy.

## Dataset layout

Structured per-run records are JSON Lines files partitioned by benchmark and backend:

```text
data/validation/records/<benchmark>/<backend>.jsonl
data/benchmark/records/<benchmark>/<backend>.jsonl
```

Each line is one record and contains its stable run ID. Timing-corrected benchmark
records carry `timing_fixed: true`, source links for both Git revisions, and the
immutable correction-amendment digest. Schemas are under
[`schemas/`](schemas/). Original canonical YAML and CSV outputs remain under their
respective phase directories.

The current combined release is under [`release/`](release/README.md): 6,600 scored
programs across 30 model/effort profiles, using the same scoring procedure applied jointly to five
campaigns. It includes Claude 5, GPT-6, Opus 5.5 and Sol 6.1, with timing-corrected measurements and
per-run source history. All 44 current cell winners have individual
analyses; superseded reviews are retained too (93 notes in total).

Codex cost estimates use exact reported token counts from retained
Codex session records.
See [token recovery and cost accounting](analysis/README.md#gpt-56-scorecost-comparison).

The original 4,620-program campaign is archived under `data/`, with its validation,
benchmarking and timing-audit counts in
[`data/release_summary.yaml`](data/release_summary.yaml). The combined release's
counts and provenance are in [`release/catalog.json`](release/catalog.json).

## Campaigns

| Campaign | Programs | Fully validated | Successful benchmarks |
| --- | ---: | ---: | ---: |
| [Original model set](data/release_summary.yaml) | 4,620 | 3,825 | 3,488 |
| [Claude 5: Fable, Opus, Sonnet](batches/20260901-162328/README.md) | 660 | 642 | 627 |
| [GPT-6: Sol, Luna, Astra](batches/20260929-135931/README.md) | 660 | 609 | 588 |
| [Opus 5.5 Medium](batches/20261002-142720/README.md) | 220 | 219 | 219 |
| [Sol 6.1 Medium and XHigh](batches/20261006-204623/README.md) | 440 | 439 | 439 |

All campaigns use the same reviewed benchmark sizes, iterations, timeouts and
resource profiles, with one warm-up and five measurements. Campaign records and
the [shared timing-correction evidence](corrections/20261001-gpt6-qt/README.md)
retain validation decisions, timing audits, scoped reruns and source revisions.

## Verify

Only Ruby's standard library is required:

```bash
ruby tools/verify_release.rb
```

This checks the release checksum manifest, source/configuration/amendment chains,
record schemas and counts, score distribution, evidence scope, forbidden artifact
patterns, repository size budgets, and a deterministic reconstruction of the combined
release. To rebuild the combined view after an intentional input update, use
`ruby tools/current_release.rb --require-reviews`, then regenerate analysis outputs
and checksums as described in [`analysis/README.md`](analysis/README.md).

## Provenance of the curated dataset

The dataset was exported using the following command:

```bash
ruby tools/export_run.rb \
  --run-dir=/home/petert/llm_para_local_evaluation/20260819-003427 \
  --replacement-run-dir=/home/petert/llm_para_local_evaluation/20260822-145159 \
  --pipeline-root=/home/petert/llm_eval/experiment \
  --baseline-root=/path/to/local-eval-2026-08-22-checkout \
  --timing-audit-root=/home/petert/llm_timing_audit/20260824-rubric2 \
  --timing-proposals-root=/home/petert/llm_timing_fixes/20260824-proposals1 \
  --timing-review-root=/home/petert/llm_timing_fixes/20260824-postfix-review1 \
  --timing-adjudication-root=/home/petert/llm_timing_fixes/20260824-postfix-adjudication1 \
  --timing-final-root=/home/petert/llm_timing_fixes/20260824-final1 \
  --replace

ruby analysis/src/timing_correction_analysis.rb
ruby tools/update_checksums.rb
ruby tools/verify_release.rb
```
