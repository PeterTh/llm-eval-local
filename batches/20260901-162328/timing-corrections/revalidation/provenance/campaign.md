# Claude 5 timing-corrected revalidation — 2026-09-28

This is a scoped revalidation of exactly the 174 corrected MPI/hybrid programs in
batch `20260901-162328`, not a restart of the original 660-program validation or a
performance benchmark. The original 642 passes and 18 failures remain preserved.

Original generated commit: `db27e2872a28b900024d318f6a3004a3a7fddfa7`.
Single timing-correction commit: `4500d708ad5c7b5d1594f93704011d6dfbca09a1`.
Isolated sparse source checkout: `/tmp/claude5-corrections-20260928-FwHKiN/generated`.
Run directory: `/home/petert/llm_para_local_evaluation/20260928-claude5-corrected-validation`.
Home uses local XFS; scratch uses local ext4. Neither is NFS.

All 174 patches compiled and all 174 independent Luna/high static reviews accepted
them with high confidence. The adjudication selection is empty, with a retained
manifest and verified empty summary; no unnecessary adjudication calls were made.
Proposal/review workers were source-only; the main pipeline performs this separate
execution-based validation using unchanged inputs, tolerances and resource limits.

Corrections by model: Fable 80 (39 MPI, 41 hybrid), Opus 49 (16 MPI, 33 hybrid),
Sonnet 45 (25 MPI, 20 hybrid). Of the 174 corrections, 150 introduce global maximum
aggregation and 24 establish a proven root-clock global envelope by moving the
start before an existing barrier. All preserve computation and non-timing behavior.
The patch changes 174 C++ files, with 783 insertions and 331 deletions; file modes,
build definitions, transcripts and metadata are unchanged.

The two conditional Floyd-Warshall hybrid cases remain outside this correction set:
Fable r2 requires N >= 4; Opus r3 requires N >= 193 with four ranks and block size 64.
These conditions must be checked when future benchmark sizes are frozen.

Progress is written atomically to `validation/all_validation_results.yaml`.
Resume only unfinished work with:

```sh
cd /home/petert/llm_eval/experiment
ruby local_evaluation.rb validate --run-dir=/home/petert/llm_para_local_evaluation/20260928-claude5-corrected-validation
```

Inspect any failure before retrying; use `--id=... --retry-failed` only for an
identified, resolved issue. Do not repeat unaffected validations. Do not modify the
core validation pipeline: both the original and corrected manifests bind its hashes.

Once all 174 pass, verify the source commit and fast-forward the home generated
repository from the original commit to the corrected commit. Preserve its unrelated
untracked `20260909-123351/` batch. Finalize the correction registry under
`/home/petert/llm_timing_fixes/20260928-claude5-final1`, then export compact evidence
to `/home/petert/llm-eval-local/batches/20260901-162328/timing-corrections`.
Preserve the original clean 660-program checkout at
`/tmp/claude5-validation-20260928-JNX71l/generated` for original-source verification.

The registry must preserve `timing_fixed`, both source revisions/digests, and both
commit-pinned GitHub URLs. Existing website components already support those links;
the new batch is not yet benchmarked, scored, integrated or published. Do not push.

## Completed

All 174 corrected programs passed all five stages on their first attempt, finishing
at approximately 15:25 UTC. Their numerical result blocks are byte-identical to all
174 corresponding original validation outputs. No validation retries were needed.
The home generated-source branch has been fast-forwarded to the single correction
commit. The final software suite passes: 106 tests, 763 assertions, no failures or
errors and three expected skips. One interim test invocation encountered the host
lock held by this validation; rerunning the full suite after completion passed.
