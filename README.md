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
- all 4,620 validation outcomes, including exact validation execution output;
- all 3,825 benchmark attempts, their measured values and wall times;
- raw diagnostic logs for failures, sequential references, and amended attempts;
- the complete 1,615-program static MPI/hybrid timing audit, 587 accepted timing-only
  corrections, and compact before/after rerun measurements;
- aggregate datasets, scoring inputs, audit records, and final scores;
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

The canonical release was produced from local run `20260819-003427`. It contains
4,620 completed validation records, 3,825 fully valid programs, 3,825 attempted
benchmarks, and 4,620 scored records. Current success/failure and score counts are in
[`data/release_summary.yaml`](data/release_summary.yaml), which is generated and
cross-checked from the curated records.

The timing audit selected all 1,615 successful MPI/hybrid measurements. Static review
classified 1,028 as valid and 587 as needing a timing-only correction. Only those 587
programs were changed and benchmarked again; the guard recorded in the release summary
proves that the other 3,238 benchmark records are unchanged. The prior complete release
is retained by the `local-eval-2026-08-22` tag.

## Verify

Only Ruby's standard library is required:

```bash
ruby tools/verify_release.rb
```

This checks the release checksum manifest, source/configuration/amendment chains,
record schemas and counts, score distribution, evidence scope, forbidden artifact
patterns, and repository size budgets.

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
