# Timing-only corrections: batch 20260901-162328

All 174 confirmed timing-invalid MPI/hybrid programs have been corrected, compiled,
independently reviewed and revalidated. Every corrected program passed all five
unchanged validation stages. All 174 numerical result blocks are byte-identical to
their corresponding original validation outputs. No performance benchmarking was run.

| Model | MPI corrections | Hybrid corrections | Total | Revalidation passes |
| --- | ---: | ---: | ---: | ---: |
| Fable 5 | 39 | 41 | 80 | 80 |
| Opus 5 | 16 | 33 | 49 | 49 |
| Sonnet 5 | 25 | 20 | 45 | 45 |
| Total | 80 | 94 | 174 | 174 |

## Source changes and review

The single generated-source commit is
`4500d708ad5c7b5d1594f93704011d6dfbca09a1`, with original parent
`db27e2872a28b900024d318f6a3004a3a7fddfa7`. The home generated-source repository has
been fast-forwarded to that commit. Exactly 174 C++ files changed: 783 insertions
and 331 deletions, with no file-mode, build-definition, transcript or metadata changes.
The other 486 programs in this batch and every earlier batch remain unchanged.

150 corrections introduce MPI_MAX aggregation of complete local durations; 24
establish a proven root-clock global envelope by placing the start before an
existing opening barrier. RoomSim totals retain the approved alternatives of a
maximum of complete local totals or a sum of maxima for sequential phases.
Canonical timing and directly derived performance output use the corrected value.
Algorithms, inputs, iteration counts, computational results and validation criteria
are unchanged. Necessary timing synchronization is within the authorized scope.

Sol/high generated proposals after a 16-case stratified pilot and main-investigator
source inspection. All 174 proposals compiled with the pinned toolchain on local
scratch. Independent Luna/high corrected-source review, likewise piloted on 16
cases, accepted all 174 with high confidence. There were no disputed or uncertain
post-fix verdicts, so the separate adjudication inventory is empty; its manifest and
verified empty summary are retained. The original-source audit's stronger reviews
and adjudications remain preserved separately.

All 348 proposal/review invocations completed without retries. Their event streams
passed the no-tool/static-only checks and are bound to source, prompt, response and
event digests. Agents did not execute or compile programs. Main-pipeline compilation
and validation are distinct from that source-only review.

## Revalidation and preserved outcomes

Scoped validation ran from approximately 14:40 to 15:25 UTC on 2026-09-28, against
the committed correction, using the unchanged five-stage pipeline, reference inputs,
tolerances and resource profiles. All 174 passed on their first attempt.
Original validation remains separate: 660 records, 642 passes and 18 failures.
No original failure was retried or reclassified, and no historical measurement or
score was replaced.

The corrected validation manifest, per-program metadata, exact runtime outputs,
reference evidence and method snapshots are retained under `../revalidation/` in
the exported artifact. `../validation-comparison.jsonl` records the supplementary
byte-exact comparison of numerical result blocks; timing/performance lines are not
part of that comparison. No claim about corrected performance follows from these
small validation runs.

The two original conditional Floyd-Warshall hybrid cases are unchanged:

- `floydwarshall_claude-fable-5-cc-medium_hybrid_r2`: requires N >= 4 with four ranks.
- `floydwarshall_claude-opus-5-cc-medium_hybrid_r3`: requires N >= 193 with four ranks
  and 64-wide blocks.

Their conditions still need checking when benchmark sizes are frozen. They retain
the original review-required status and are not silently treated as unconditional
timing passes.

## Original and corrected source access

Every entry in [corrections.jsonl](corrections.jsonl) retains `timing_fixed: true`,
the original issue categories, both source commits/digests/tree IDs, and separate
`original_source_url` and `corrected_source_url` links pinned to those revisions.
Both source versions therefore remain available in Git without duplicate source
files in this artifact repository.

The existing website already supports the timing-fixed indicator and separate
original/corrected source links. These records use that established representation,
joining by `program_id`. This batch has not yet been benchmarked, scored, integrated
into the website's performance data, or published. The corrected commit is local;
no Git push was performed. Future integration must combine the preserved original
validation with this affected-program revalidation and the correction registry,
without re-executing unaffected programs.

## Retention and verification

Persistent results are under home on local XFS; temporary agent/source/compiler
workspaces used local `/tmp` on ext4. Neither is NFS. The compact export retains
decisions, exact edit proposals, compile outcomes, validation evidence and method
snapshots, but excludes binaries, build trees, full source copies and raw agent
event streams. Duplicate proposal snapshots are omitted only after proving they
can be reconstructed byte-for-byte from the retained proposals and inventory order.

The final software test suite passed: 106 tests, 763 assertions, zero failures or
errors, three expected environment-dependent skips. One interim suite invocation
encountered the host-performance lock held by this validation; the full suite was
rerun successfully after validation released it. No generated-program validation
was affected or retried.

The pre-existing unrelated dirty experiment/artifact worktrees and untracked
`20260909-123351/` generated batch were preserved. Only the accepted generated-source
corrections were committed in this task; artifact/tooling changes remain in their
existing worktrees. No release tag, push, deployment or full-corpus rerun was made.

Global release verification and all three nested batch/correction/revalidation
checksum checks passed. The complete scientific artifact is approximately 84.1 MiB,
including approximately 9.3 MiB of new correction evidence, within the 100 MiB cap.
The historical release still has 4,620 validation records, 3,825 benchmark attempts
(3,488 successful), and 4,620 score records.
