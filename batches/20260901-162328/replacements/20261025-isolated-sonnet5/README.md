# Sonnet 5: seven scoped replacements

These records replace exactly seven observations in the Claude 5 batch. Six pass
scientific validation and benchmarking. `roomsim_claude-sonnet-5-cc-medium_hybrid_r3`
fails the existing numerical-output comparison and remains a validation failure,
without a benchmark result. No ordinary generation or scientific failure was retried.

The original per-observation Claude Code versions, Sonnet 5 model, medium effort,
prompt, tool/plugin restrictions and four-hour budget were retained. Fresh
mount-allowlist isolation prevents access to other observations or evaluator data.
Compact generation, isolation and audit-selection evidence is under `generation/`;
programs and transcripts remain solely in the generated-source repository.

All six passing MPI/hybrid programs received static timing review. Luna reviewed
first; Sol 6.1 adjudicated only uncertainty or disagreement. Nbody MPI r3 and Roomsim
MPI r5 required maximum-per-rank timing reductions, independently reviewed and
committed together. Both passed scoped revalidation with unchanged numerical output.

- Fresh generated-source commit: `9ca4eb864529503d811edb1352c8e5b9a6f71c83`.
- Timing-corrected commit: `ce15f07db28d3d894f004d50f08352943caa42a8`.
- Superseded source is preserved in Git history; file identities are in `generation/superseded-files.json`.
- [Resolved timing decisions](timing-audit/resolved-selection.json) and [correction evidence](timing-corrections/README.md).
- [Benchmark completion](completion/benchmark-completion-review.json): the established 44-cell configuration, one warmup and five measurements, no retries; both canary programs' measurements were reused.

The [release guard](release-guard.json) binds all 653 unaffected Claude 5 records.
The other 7,693 release observations and scores are unchanged. No new cell winner
was introduced. The 17 audited GPT-5.6 cases are outside this replacement scope.
`aggregate/` retains the exact native CSV and accounting evidence; method files and
SHA-256 checksums retain provenance without binaries or build trees.
