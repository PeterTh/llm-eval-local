# Claude 5 timing-only correction campaign — 2026-09-28

Authorized: correct the 174 confirmed timing-invalid MPI/hybrid programs in batch
20260901-162328; independently review, compile and revalidate affected programs;
commit accepted generated-source changes together and retain original/corrected
Git links and timing-fixed metadata for eventual website integration.

Do not change the two conditional Floyd-Warshall programs, algorithms, inputs,
iteration counts, validation criteria, or unrelated user work. Do not benchmark
or push. The original validation and historical performance release stay intact.

Source base: db27e2872a28b900024d318f6a3004a3a7fddfa7, currently HEAD in
/home/petert/llm_para_experiments. Its unrelated untracked 20260909-123351 batch
must remain untouched.
Audit: /home/petert/llm_timing_audit/20260928-claude5/final.
Proposals: /home/petert/llm_timing_fixes/20260928-claude5-proposals1.
Independent review: /home/petert/llm_timing_fixes/20260928-claude5-postfix-review1.
Adjudication: /home/petert/llm_timing_fixes/20260928-claude5-postfix-adjudication1.
Final registry: /home/petert/llm_timing_fixes/20260928-claude5-final1.
Temporary workspace: /tmp/claude5-corrections-20260928-FwHKiN (local ext4).
Persistent evidence lives under home (local XFS, not NFS).

Phases: Sol/high proposal pilot (16 cases, 4 workers), main-investigator source
quality gate and compile check, then full proposal run (16 workers). Compile all
accepted proposals on local scratch. Independent Luna/high review of corrected
sources, followed by Sol/xhigh adjudication of disputed or uncertain decisions.
Workers are source-only with execution tools disabled; attempts are immutable and
bound to source/response/event digests. Resolve failures only for affected IDs.

Create one source commit on an isolated local clone and revalidate only the 174
corrected programs before fast-forwarding the original repository. Preserve the
original validation checkout and results. The final correction registry uses the
existing original_source_url/corrected_source_url and timing_fixed fields; export
compact evidence to llm-eval-local without binaries, full source copies or repeated
raw agent streams. No historical benchmark rerun is justified by these local fixes.

## Reviewed correction checkpoint

All 174 proposals compiled successfully. Independent corrected-source review then
accepted all 174 with high confidence; the adjudication selection is empty and has
its own verified manifest and summary. All 348 proposal/review attempts completed
without retries, and their event streams passed the no-tool/static-only checks.
The 16-case proposal and independent-review pilot quality gates are retained.

The single generated-source commit is
`4500d708ad5c7b5d1594f93704011d6dfbca09a1`, parent
`db27e2872a28b900024d318f6a3004a3a7fddfa7`. It changes exactly the 174 intended C++
files (783 insertions, 331 deletions) with no mode, build-definition, transcript or
metadata changes. Every corrected source digest matches its review dossier.
The commit has been fetched into the home repository's object store; its checked-out
branch remains at the original commit until revalidation completes.

Scoped revalidation started at approximately 14:40 UTC, using
`/home/petert/llm_para_local_evaluation/20260928-claude5-corrected-validation`.
The initial corrected validations pass all five unchanged stages. No performance
benchmarking has been launched. See that run's `campaign.md` for exact resume steps.
Current tooling tests: 105 tests, 759 assertions, no failures/errors, three skips.

## Completed correction and revalidation

At approximately 15:25 UTC, all 174 corrected programs had passed every validation
stage on their first attempt. Their numerical result blocks match their original
validation outputs byte-for-byte. The home generated-source branch was then
fast-forwarded to the single correction commit `4500d708ad5c7b5d1594f93704011d6dfbca09a1`.
The final registry and report are under `20260928-claude5-final1`; compact export is
under the supplementary batch's `timing-corrections/` directory in llm-eval-local.
The final software suite passes: 106 tests, 763 assertions, no failures/errors,
three expected skips. No performance benchmarking, full rerun or push was performed.
