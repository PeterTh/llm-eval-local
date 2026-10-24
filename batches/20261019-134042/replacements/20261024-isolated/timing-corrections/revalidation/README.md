# Corrected-source revalidation: 20261019-134042

This directory contains corrected-source validation evidence. All 6 programs
subsequently passed benchmarking and are included in the current release;
measurements are retained under the scoped batch's `benchmark/` directory.

Generated-source commit: `ce4a44804c3a5dca64f03c4ec524df959238940f`.
Validation: 6 records, 6 passing all five stages.
See `summary.json` for backend counts and completed audit stages.
The [correction report](../final/report.md) describes the accepted timing-only changes.

`validation/records.jsonl` retains each result's metadata, staging provenance,
exact execution output, commands, exit statuses, wall times, and source-log
hashes. Successful compiler output is omitted; failure diagnostics remain.
The parent correction directory retains proposals and independent reviews.
Original generated code, transcripts, binaries, and build trees are not copied.

Every artifact is covered by `checksums.sha256`. Exact method files are under
`method/`; `method/layout.json` maps their stored paths to the experiment-repo
paths needed to reconstruct a runnable checkout. This avoids modifying frozen
code merely to accommodate the artifact repository's flat snapshot layout.
