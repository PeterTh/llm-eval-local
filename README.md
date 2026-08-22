# Local Validation and Benchmark Artifact

This repository contains the local re-validation, performance benchmarking, scoring,
and analysis artifacts for:

> **Evaluating the Parallelization Capabilities of State-of-the-art Agentic Large
> Language Models**<br>
> Peter Thoman and Philipp Gschwandtner, University of Innsbruck<br>
> Accepted at Euro-Par 2026

The LLM-generated programs are intentionally not duplicated here. They are retained
in [`llm-eval-generated`](https://github.com/PeterTh/llm-eval-generated) and are joined
to these records by run ID, source batch, repository commit, and staged-content
SHA-256 digest.

## What is retained

- immutable provenance, environment, preflight, calibration, and amendment records;
- all 4,620 validation outcomes, including exact validation execution output;
- all 3,825 benchmark attempts, their measured values and wall times;
- raw diagnostic logs for failures, sequential references, and amended attempts;
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

Each line is one record and contains its stable run ID. Schemas are under
[`schemas/`](schemas/). Original canonical YAML and CSV outputs remain under their
respective phase directories.

The canonical release was produced from local run `20260819-003427`. It contains
4,620 completed validation records, 3,825 fully valid programs, 3,825 attempted
benchmarks, 3,488 successful benchmark records, and 337 benchmark failures.

## Verify

Only Ruby's standard library is required:

```bash
ruby tools/verify_release.rb
```

This checks the release checksum manifest, source/configuration/amendment chains,
record schemas and counts, score distribution, evidence scope, forbidden artifact
patterns, and repository size budgets.

## Rebuild the curated dataset

The exporter reads, but never modifies, the durable evaluation workspaces:

```bash
ruby tools/export_run.rb \
  --run-dir=/home/petert/llm_para_local_evaluation/20260819-003427 \
  --replacement-run-dir=/home/petert/llm_para_local_evaluation/20260822-145159 \
  --pipeline-root=/home/petert/llm_eval/experiment \
  --replace

ruby tools/verify_release.rb
```

Temporary assembly is performed under local `/tmp`; the persistent checkout and
published results live under `/home` and in GitHub.
