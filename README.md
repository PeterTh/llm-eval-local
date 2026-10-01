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
- all 5,280 validation outcomes, including exact validation execution output;
- all 4,467 benchmark attempts (4,115 successful), measured values and wall times;
- raw diagnostic logs for failures, sequential references, and amended attempts;
- static MPI/hybrid timing audits covering 1,939 programs, 761 accepted timing-only
  corrections, and compact before/after measurements where both were collected;
- aggregate datasets, scoring inputs, audit records, and final scores;
- compact, provenance-bound Codex usage records for 1,980 GPT-5.6 and 660 GPT-6 runs;
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

The current combined release is under [`release/`](release/README.md): 5,280 scored
programs across 24 models, using the same scoring procedure applied jointly to both
campaigns. It joins the original records below with the Claude 5 batch; no historical
measurements are replaced. The website and current score/cost figures use this view.
All 44 current cell winners have individual analyses; the 44 previous analyses are
also retained (68 notes in total).

Recovered GPT-5.6 token counts are applied as a metadata-only release overlay;
raw campaign records, measurements, and scores are unchanged. The GPT-6 generation
campaign is complete, but its performance results are not yet part of this release.
See [token recovery and cost accounting](analysis/README.md#gpt-56-scorecost-comparison).

The historical release was produced from local run `20260819-003427`. It contains
4,620 completed validation records, 3,825 fully valid programs, 3,825 attempted
benchmarks, and 4,620 scored records. Current success/failure and score counts are in
[`data/release_summary.yaml`](data/release_summary.yaml), which is generated and
cross-checked from the curated records.

The timing audit selected all 1,615 successful MPI/hybrid measurements. Static review
classified 1,028 as valid and 587 as needing a timing-only correction. Only those 587
programs were changed and benchmarked again; the guard recorded in the release summary
proves that the other 3,238 benchmark records are unchanged. The prior complete release
is retained by the `local-eval-2026-08-22` tag.

## Supplementary batches

[Batch 20260901-162328](batches/20260901-162328/README.md) contains validation-first
evidence for Fable 5, Opus 5 and Sonnet 5: 642/660 validation passes and a static
audit of 324 passing MPI/hybrid programs (148 valid, 174 timing-correction
candidates, two size-dependent cases). See the
[audit report](batches/20260901-162328/timing-audit/primary/final/report.md).
All 174 candidates now have accepted timing-only corrections and passed scoped
revalidation, with numerical result blocks identical to their original runs. See
the [correction report and both source revisions](batches/20260901-162328/timing-corrections/final/report.md).
The two size-dependent cases remain unchanged; both conditions hold at the inherited
hybrid benchmark size. [Benchmarking is complete](batches/20260901-162328/benchmark/README.md):
627/642 successful, using the historical sizes, iterations, timeouts and resource
profiles, with one warm-up and five measurements. The 15 failures comprise 14
timeouts and one MPI gather crash. The batch is included in the combined release,
website data generation, and analysis tables. Both original and timing-corrected
source revisions are linked per run. Historical raw data remains unchanged.

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
