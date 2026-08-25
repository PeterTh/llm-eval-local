# Method snapshot

`pipeline/` is the exact textual source snapshot named by the final immutable
pipeline amendment. Its aggregate source digest is recorded in
`data/provenance/repositories.yaml`; individual file digests are in
`pipeline-files.sha256`.

`timing-audit/` contains the static-audit, correction, independent-review,
adjudication, finalization, and scoped-rerun tooling. The run-time agent runner
snapshots, prompts, and schemas are also retained with the compact evidence under
`data/timing-audit/`; `timing-audit-files.sha256` binds this readable method snapshot.

Only the local validation, calibration, benchmark, aggregation, and scoring sources
bound into the scientific run are copied. The complete development history and
historical Slurm workflow remain in
[`llm-eval-experiment`](https://github.com/PeterTh/llm-eval-experiment).
