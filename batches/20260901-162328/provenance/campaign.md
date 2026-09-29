# Claude 5 validation and timing audit

Batch: `20260901-162328` (660 programs; 330 MPI/hybrid).
Pinned generated-source commit: `db27e2872a28b900024d318f6a3004a3a7fddfa7`.
Original source repository: `/home/petert/llm_para_experiments`.
Isolated sparse checkout: `/tmp/claude5-validation-20260928-JNX71l/generated`.
Validation run: `/home/petert/llm_para_local_evaluation/20260928-claude5-validation`.

The sparse checkout contains only the committed batch. No original generated source
is modified. `/tmp` is local ext4; the evaluation directory under home is local XFS,
not NFS. Both preflight and initial baseline tests passed. Validation uses the
existing five-stage criteria, without calibration or performance benchmarking.

Progress is recorded atomically in `validation/all_validation_results.yaml`.
Resume only incomplete validations with:

```sh
cd /home/petert/llm_eval/experiment
ruby local_evaluation.rb validate --run-dir=/home/petert/llm_para_local_evaluation/20260928-claude5-validation
```

Do not use `--retry-failed` without inspecting the failure; generated-program
failures are experimental outcomes, not automatically retryable infrastructure
errors. Never restart unrelated validations.

After all 660 validation records exist, prepare the audit:

```sh
ruby tools/timing_audit/bin/timing_audit.rb prepare \
  --validation-run=/home/petert/llm_para_local_evaluation/20260928-claude5-validation \
  --source-root=/home/petert/llm_para_experiments \
  --output=/home/petert/llm_timing_audit/20260928-claude5
ruby tools/timing_audit/bin/timing_audit.rb run \
  --output=/home/petert/llm_timing_audit/20260928-claude5 --scope=trial --jobs=4
```

Inspect the 16-program trial against the source before running `--scope=full
--jobs=16`. Workers use `gpt-5.6-luna` / `high` and are restricted to source-only
review; their event streams are checked for tool use. The timing contract is maximum
completed per-rank time or a proven equivalent global makespan, including device
completion and the actual non-validation execution path.

Independent Luna review covers invalid, ambiguous, non-high-confidence, and
valid-without-explicit-MPI_MAX cases. Blind `gpt-5.6-sol` / `xhigh` adjudication covers
disagreements and unresolved uncertainty. Retain ambiguity if static proof is not
possible. No generated-source corrections or benchmark runs are authorized by this
campaign; report proposed timing-only corrections after the audit.

Export compact validation/audit evidence with
`tools/timing_audit/bin/export_validation_audit.rb` to
`/home/petert/llm-eval-local/batches/20260901-162328`, then refresh and verify artifact
checksums. Preserve the canonical historical release and unrelated uncommitted work.
Do not export binaries, source copies, or repeated raw agent streams.

## Validation outcome and failure review

Validation completed on 2026-09-28: 642 of 660 programs passed all five stages.
There were 161 CUDA, 160 hybrid, 164 MPI, and 157 OpenMP passes (165 candidates
per backend), leaving 324 MPI/hybrid programs eligible for static timing review.
No performance benchmarking was performed and no failed program was retried.

The 18 rejected programs comprise one backend-detection failure (Black-Scholes
Opus CUDA r5 also uses actual OpenMP pragmas), 16 numerical output mismatches
(15 RoomSim and one QTClustering), and one execution failure. Numerical comparisons
use the unchanged reference inputs and tolerances; the RoomSim tolerances remain
50 for sums and 5 for distance samples. Build and execution logs for the numerical
failures show successful completion, not infrastructure errors.

The execution failure is `stencil3d_claude-sonnet-5-cc-medium_hybrid_r2`. Its source
`stencil3d/stencil3d.cpp:184-187` explicitly calls `omp_set_num_threads` using
`hardware_concurrency()/nodeSize`, overriding the supplied `OMP_NUM_THREADS=8`.
The recorded output confirms 64 threads/rank for four ranks. These 256 OpenMP
threads plus MPI/CUDA overhead exceed the existing 256-task validation limit;
libgomp reports thread-creation failure. This is retained as a failure under the
unchanged resource profile, not a transient server or launcher failure. An identical
retry would not address the source/profile conflict. No resource-policy exception
or algorithm/source modification was made to turn it into a pass.

Before the pilot, the audit runner explicitly disabled shell/unified execution,
web search, hooks, and external integrations, while retaining the read-only sandbox,
source-only prompt, and successful-attempt event checks. This configuration was
checked against local Codex 0.158.0 capabilities and the official configuration
reference: https://learn.chatgpt.com/docs/config-file/config-reference.

## Static audit checkpoint

The primary audit is complete: 324 source-only reviews (102 valid, 221 invalid,
one ambiguous). These are screening verdicts, not final conclusions.
The 16-case pilot and main-agent quality gate are retained in
`/home/petert/llm_timing_audit/20260928-claude5/pilot-review.md`.

The original prompt over-flagged some root-controlled global makespans. Both a
blind three-case Sol check with the original prompt and a five-case blind Luna
check with refined work-start-dependency guidance are retained separately:
`20260928-claude5-pilot-adjudication` and `20260928-claude5-pilot-review` under
`/home/petert/llm_timing_audit`. The refined check matched all five source inspections.
The full method therefore requires refined independent review of every flagged
case, not acceptance of primary verdicts alone.

The full refined independent review selected 222 cases and was launched with
16 Luna/high workers at approximately 13:08 UTC on 2026-09-28. It is resumable with:

```sh
ruby tools/timing_audit/bin/timing_priority_review.rb run --output=/home/petert/llm_timing_audit/20260928-claude5-priority --jobs=16
```

After it completes, prepare blind adjudications with:

```sh
ruby tools/timing_audit/bin/timing_priority_review.rb prepare-adjudication \
  --main=/home/petert/llm_timing_audit/20260928-claude5 \
  --review=/home/petert/llm_timing_audit/20260928-claude5-priority \
  --output=/home/petert/llm_timing_audit/20260928-claude5-adjudication \
  --context=/home/petert/llm_para_local_evaluation/20260928-claude5-validation/platform-context.txt
ruby tools/timing_audit/bin/timing_audit.rb run \
  --output=/home/petert/llm_timing_audit/20260928-claude5-adjudication \
  --scope=full --jobs=16 --model=gpt-5.6-sol --effort=xhigh
```

The platform context is a successful compile-only proof that the actual nvcc/GCC13
LP64 toolchain gives the chrono millisecond count exactly type `long`. It contains
the probe source and invocation, not a prior verdict. No probe executable was run;
the object remains only in `/tmp` and is not exported.

The initial diagnostic-checker incident is preserved at
`/home/petert/llm_timing_audit/20260928-claude5-initial-pilot` and compactly under
the main audit's `recovery/`. Eight completed responses were reused. Subsequent
primary citation-format/API-capacity retries affected only their own records; no
validation was repeated. Review/adjudication schemas now constrain citation ranges
to the already-required format to avoid unnecessary formatting retries.

The validation-only supplementary export already exists in
`/home/petert/llm-eval-local/batches/20260901-162328` (8,366,430 logical bytes before
audit evidence). Re-export after finalization with the primary, priority,
adjudication, pilot-adjudication, and pilot-review roots, then refresh global
checksums and run the artifact verifier. No source correction, benchmarking,
commit, or push has been performed in this campaign.

Independent review completed: 222/222 (47 valid, 174 invalid, one ambiguous).
There are 48 verdict disagreements. Including category/fixability disagreements
and unresolved uncertainty, 181 blind Sol/xhigh adjudications were prepared and
launched at approximately 13:24 UTC. Their prepared root is
`/home/petert/llm_timing_audit/20260928-claude5-adjudication`.
The current full test suite passes: 99 tests, 719 assertions, zero failures/errors,
three expected skips. Finalization/export/verification were pending at this checkpoint.

## Completed audit

The 181 blind adjudications finished: 45 valid, 134 invalid and two ambiguous.
Final source inspection selected one further case for a blind supplemental review,
`spmv_claude-opus-5-cc-medium_hybrid_r1`, because the earlier reviewers assumed
multiple visible GPUs per rank. The recorded wrapper exposes exactly one GPU per
rank; this forces a single device worker and makes the complete MPI_MAX timer valid.
The supplemental source-only Sol/xhigh review confirmed that proof. Its selection,
verified GPU-profile context, original reviews and new result are retained in the
separate `20260928-claude5-supplemental` root, without replacing prior evidence.

Final result: 324 reviewed, 148 valid, 174 invalid/timing-only correction candidates,
and two conditional cases. The two Floyd-Warshall hybrid conditions under four
ranks are Fable r2 with N >= 4 and Opus r3 with N >= 193 (64-wide blocks).
Benchmark sizes are not frozen; these remain ambiguous with a null
`timing_fix_required` value and `timing_review_required: true`.
No source correction, performance benchmarking, commit or push was performed.

The final report is `20260928-claude5/final/report.md`; all candidate IDs, source
citations, retained review verdicts and proposed minimal fixes are beside it.
The full software suite passes: 99 tests, 729 assertions, no failures/errors,
three expected skips. The artifact export includes all six completed audit roots
(primary, priority, adjudication, supplemental, and both pilot diagnostic reviews).
