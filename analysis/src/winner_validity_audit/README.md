# Winner validity audit, 2026-11-03

This is a diagnostic research audit, not a new release-validation policy. See
the [research note](../../notes/2026-11-03-winner-validity-audit.md) for findings
and the distinction between winner checks and deliberately corrupted reference
counterexamples.

## Verify retained evidence

From the artifact-repository root:

```bash
ruby analysis/src/winner_validity_audit/verify.rb --sources
ruby analysis/src/winner_validity_audit/verify.rb --coverage
```

These commands are read-only. They reconstruct comparisons with the frozen
external comparator, verify digests and the frozen 44-winner selection, and
optionally verify generated source blobs. They do not run compiled programs.
The second command prints the per-winner coverage table to stdout.

`WINNER_AUDIT_GENERATED` can override the generated-output Git repository, which
defaults to `/home/petert/llm_para_experiments`. Omit `--sources` if that repository
is unavailable. `WINNER_AUDIT_RELEASE` can override the artifact repository used
to read the frozen release/comparator Git objects.

## Explicit host reproduction

Only run this when generation/validation/benchmarking is idle. It needs the
documented evaluation host, GPUs, MPI, native containment permissions and enough
local space. The driver takes the native performance lock and refuses to run if
`llmtest` has active processes. It never changes published validation or benchmark
records. All builds/execution belong in a fresh **local `/tmp` workspace**.

The commands below assume the original input and generated-output repositories
remain at their documented home paths. All effective source revisions are read
from Git, not from their potentially changed working trees. Source-verified
build caches are reused if present; otherwise the ordinary native build path
is used. Copying the driver into `/tmp` is intentional: it writes scratch data
alongside itself and refuses to run from a repository/home directory.

```bash
set -e
audit_workspace=$(mktemp -d /tmp/winner-validity-reproduction.XXXXXX)
audit_source="$PWD/analysis/src/winner_validity_audit"
git worktree add --detach "$audit_workspace/release" c75207d5608801d820eceffe4ffeae6576e4be51
git -C /home/petert/llm_eval/experiment worktree add --detach "$audit_workspace/method" f64915ac0ae289ee9333c4c52e98c9af2f6dfd54
cp "$audit_source/inventory.rb" "$audit_source/probe.rb" "$audit_source/counterexamples.rb" "$audit_source/comparator_counterexample.cpp" "$audit_workspace/"
export WINNER_AUDIT_RELEASE="$audit_workspace/release"
export WINNER_AUDIT_EXPERIMENT="$audit_workspace/method"
ruby "$audit_workspace/inventory.rb"
ruby "$audit_workspace/probe.rb" prepare
ruby "$audit_workspace/probe.rb" run
ruby "$audit_workspace/probe.rb" branch
ruby "$audit_workspace/counterexamples.rb"
```

The unrelated uncommitted `experiment.rb` additions are not used by these
drivers. The sequential input commit is
`2bc11aeac658a87b5cae25d03e0669f65d32922e`.

The retained driver uses the corrected 512-task limit for benchmark-topology
checks; it deliberately does **not** reproduce the eleven original startup
failures. The `mpi128_retry` mode was used only to replace those diagnostic
launches. Reproduction is correctness work, not a replacement performance run;
do not append its timings to published measurements.

`comparator_counterexample.cpp` includes the frozen input implementation with its
main renamed in a separate diagnostic translation unit, then deliberately
changes a completed output vector before calling the original checker. It does
not edit the reference source or any winner and must not be mistaken for a model
failure. `counterexamples.rb` also compares unchanged SpMV outputs for one and
eleven iterations.

## Original evidence export

`export.rb` packages the original audit workspace into a new destination:

```bash
ruby analysis/src/winner_validity_audit/export.rb /path/to/original-local-audit-workspace /tmp/new-winner-audit-evidence
```

The original export retains all 85 main diagnostic attempts: 59 successful
winner checks, 15 reference checks and 11 superseded startup failures, plus the
three comparator counterexamples. It records build/source bindings, full
successful numerical output, and bounded hashed failure excerpts. It includes no
binaries, repeated generated-source trees, credentials, model transcripts or
duplicate historical validation records. `coverage.json` is the focused manual
source-review annotation keyed by the frozen winner cells.

The recorded original-driver digests describe the temporary scripts actually
used. Retained reproduction drivers add local-workspace/frozen-release guards
and a binary-binding fallback for rebuilt caches; they are not falsely presented
as byte-identical to those original scripts.
