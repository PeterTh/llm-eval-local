# Beam 1.0 Medium in OpenCode: 20261025-170121

This batch retains 220 generation outcomes, validation, static timing review,
timing-only corrections and benchmarks. It is included in the combined release.

Generated-source commit: `74652eee82e2473660a7e75f3ad5d77fd0e3759c`.
Validation: 180 passed the native stages; one additional source-pinned
Unstructured external-validation failure leaves 179 eligible programs.
Benchmarking: 145 successes and 34 failures (31 warm-up timeouts, two timing-output
parse failures and one program exit). These ordinary program failures are retained
without retries. All measurements use the established sizes and resource profiles.
See `summary.json` for native validation counts and completed audit stages,
and `benchmark/` for measurement records.
The human-readable timing findings are in
[the audit report](timing-audit/primary/final/report.md), and machine-readable
decisions in `timing-audit/primary/final/decisions.jsonl`. An ambiguous decision
has `timing_review_required: true` and `timing_fix_required: null`, not a pass.

`validation/records.jsonl` retains each result's metadata, staging provenance,
exact execution output, commands, exit statuses, wall times, and source-log
hashes. Successful compiler output is omitted; failure diagnostics remain.
`timing-audit/` retains inventories, exclusions, source-grounded findings,
independent reviews, adjudications, and compact attempt provenance.
Original generated code, transcripts, binaries, and build trees are not copied.

Every artifact is covered by `checksums.sha256`. Exact method files are under
`method/`; `method/layout.json` maps their stored paths to the experiment-repo
paths needed to reconstruct a runnable checkout. This avoids modifying frozen
code merely to accommodate the artifact repository's flat snapshot layout.

## Timing-only corrections

45 programs now have accepted, revalidated timing-only corrections.
Both original and corrected Git revisions are retained in the
[correction registry and report](timing-corrections/README.md).
All 45 corrections passed native revalidation, and the five applicable corrected
Unstructured programs passed the external check. Eleven independent full-result
replicas required no timing correction. Local timing is valid for these replicas,
but multiple primary timing outputs still fail the unchanged benchmark parser.

There are no new cell winners. The [winner comparison](../../analysis/notes/2026-10-30-beam10-opencode-winner-context.json)
retains the preceding-release comparison; [pricing and accounting](../../analysis/notes/2026-10-30-beam10-opencode-pricing.md)
cover 219 complete usage records and one explicit partial record. Generated
programs and transcripts remain in the source repository, not this package.
