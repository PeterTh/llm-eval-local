# Haiku 5.5 timing correction revalidation

These records cover the unchanged five-stage validation of the 33 timing-corrected
programs. All passed. Their performance measurements are retained separately in
the parent batch's [benchmark records](../../benchmark/records/).

Generated-source commit: `778f868b8e30433e60115c46bf01dbf84c609765`.
Validation: 33 records, 33 passing all five stages.
See `summary.json` for backend counts and the parent
[correction registry](../final/corrections.jsonl) for original and corrected sources.

`validation/records.jsonl` retains each result's metadata, staging provenance,
exact execution output, commands, exit statuses, wall times, and source-log
hashes. Successful compiler output is omitted; failure diagnostics remain.
Original generated code, transcripts, binaries, and build trees are not copied.

Every artifact is covered by `checksums.sha256`. Exact method files are under
`method/`; `method/layout.json` maps their stored paths to the experiment-repo
paths needed to reconstruct a runnable checkout. This avoids modifying frozen
code merely to accommodate the artifact repository's flat snapshot layout.
