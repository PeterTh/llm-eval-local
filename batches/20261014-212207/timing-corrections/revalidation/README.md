# Sonnet 5.5 timing correction revalidation

All 71 timing-corrected programs passed the unchanged five-stage scientific
validation. These scoped records supplement, rather than replace, the original
validation outcomes. Subsequent measurements are retained under
[benchmark evidence](../../benchmark/) and included in the combined release.

Generated-source commit: `6196b2ba8d2509ff0a7ba87d17d846a479a39282`.
Validation: 71 records, 71 passing all five stages.
See `summary.json` for backend counts, the
[correction report](../final/report.md) for accepted changes, and the
[resolved audit decisions](../../timing-audit/resolved-selection.json) for the
original timing findings.

`validation/records.jsonl` retains each result's metadata, staging provenance,
exact execution output, commands, exit statuses, wall times, and source-log
hashes. Successful compiler output is omitted; failure diagnostics remain.
Original generated code, transcripts, binaries, and build trees are not copied.

Every artifact is covered by `checksums.sha256`. Exact method files are under
`method/`; `method/layout.json` maps their stored paths to the experiment-repo
paths needed to reconstruct a runnable checkout. This avoids modifying frozen
code merely to accommodate the artifact repository's flat snapshot layout.
