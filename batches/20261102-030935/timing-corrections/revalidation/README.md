# Corrected-source revalidation: 20261102-030935

This directory retains the unchanged scientific validation of exactly the 22
timing-corrected programs. All passed, with no retries. Their later benchmark
measurements are retained in the [parent batch](../../README.md) and included in
the combined release.

Generated-source commit: `db69dadaac5ae1d55b85e40af2cf6a59e07cf7e4`.
Validation: 22 records, 22 passing all five stages.
See `summary.json` for backend counts and the
[correction registry](../final/corrections.jsonl) for source history and accepted
timing-only changes.

`validation/records.jsonl` retains each result's metadata, staging provenance,
exact execution output, commands, exit statuses, wall times, and source-log
hashes. Successful compiler output is omitted; failure diagnostics remain.
The parent correction directory retains source-grounded proposals, independent
reviews, compilation outcomes and compact attempt provenance.
Original generated code, transcripts, binaries, and build trees are not copied.

Every artifact is covered by `checksums.sha256`. Exact method files are under
`method/`; `method/layout.json` maps their stored paths to the experiment-repo
paths needed to reconstruct a runnable checkout. This avoids modifying frozen
code merely to accommodate the artifact repository's flat snapshot layout.
