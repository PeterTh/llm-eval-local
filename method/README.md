# Method snapshot

`pipeline/` is the exact 13-file textual source snapshot named by the final immutable
pipeline amendment. Its aggregate source digest is recorded in
`data/provenance/repositories.yaml`; individual file digests are in
`pipeline-files.sha256`.

Only the local validation, calibration, benchmark, aggregation, and scoring sources
bound into the scientific run are copied. The complete development history and
historical Slurm workflow remain in
[`llm-eval-experiment`](https://github.com/PeterTh/llm-eval-experiment).
