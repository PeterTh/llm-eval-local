# Haiku 5.5 Medium

This campaign contributes 220 programs to the [combined release](../../release/README.md).
Of these, 219 passed all five native validation stages and all 219 completed
benchmarking successfully. The remaining program,
`nbody_claude-haiku-5.5-cc-medium_hybrid_r2`, rejected the standard one-visible-GPU
per-rank environment. Its validation failure is retained without repair or retry.

The campaign invokes `claude-haiku-5-5` at medium effort through the shared Claude
Code harness. All 220 generation observations completed normally, with no provider
retries or timeouts. The production preflight is included, not repeated.
`generation/` retains the frozen method, executable identity, observations and
account-cleanup evidence. Original programs and transcripts remain in Git.

## Validation and timing review

`validation/records.jsonl` retains every initial outcome, exact execution output,
staging provenance, commands, exit status, wall time and source-log hashes.
Successful compiler output is omitted; failure diagnostics remain.

Timing review covers 119 unique implementations: all 109 passing MPI/hybrid
programs and all 20 passing QT-clustering programs, with ten in both groups.
The final decisions are 86 valid and 33 requiring timing-only correction, with
no unresolved cases. The [resolved selection](timing-audit/resolved-selection.json)
combines the general audit with the all-backend QT timing-boundary review.

Luna performs the primary and independent reviews; Sol adjudicates uncertainty
or disagreement. Review policy and retained operational recovery evidence are
under `timing-audit/` and `completion/`. All 33 patches compiled, received
high-confidence acceptance from independent Luna reviews, and passed unchanged
native revalidation. No post-fix Sol adjudication was needed.

The [correction registry](timing-corrections/final/corrections.jsonl) links both
versions of every corrected implementation:

- Original commit: `71ba7cc523997c8fd1537d7a8159b583f260793d`.
- Single correction commit: `778f868b8e30433e60115c46bf01dbf84c609765`.

## Benchmarking and integration

The 219 successful benchmarks comprise 186 unchanged and 33 timing-corrected
programs. All 44 established cell sizes, iteration counts, timeouts and resource
profiles are unchanged. Each program has one warmup and five measurements;
the four accepted canaries were reused. There were no benchmark retries.
Structured records are under `benchmark/records/`, with frozen configuration
and source-amendment evidence under `benchmark/provenance/`.

Haiku introduces no new cell winners. The
[comparison snapshot](../../analysis/notes/2026-10-14-haiku55-winner-context.json)
confirms that all 6,600 prior observations are unchanged; 84 scores change only
through joint thresholds. [Request-context pricing](../../analysis/notes/2026-10-14-haiku55-pricing.md)
uses retained input/cache counts and explicitly labeled output-count derivations
for mixed-tier sessions. Original token totals remain unchanged.

Every scientific artifact is covered by `checksums.sha256`. Method layouts map
stored files to their original paths and reuse identical retained content.
Generated sources, binaries, build trees and raw review-agent streams are excluded.
