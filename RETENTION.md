# Artifact Retention Policy

## Principle

Retain scientific observations, decisions, provenance, and the minimum evidence needed
to audit them. Do not retain execution workspaces or artifacts reproducible from the
published program sources, benchmark sources, pipeline source, and documented system.

## Included

- Canonical manifests, configurations, preflights, amendments, aggregates, thresholds,
  score records, and their original digest sidecars.
- A portable record for every validation and benchmark ID.
- Exact validation stdout/stderr for every executed validation. Successful configure
  and build logs are omitted because their outcome and relevant result are recorded.
- Configure/build logs and the exact validation command for failed validations.
- All raw execution logs for failed benchmarks.
- Sequential-reference logs and metadata.
- Superseded attempts explicitly covered by an immutable amendment.
- Final static timing-audit decisions, compact independent-review/adjudication
  summaries, timing-only correction records, and before/after rerun measurements.
- Original and timing-corrected generated-source Git commits and direct per-program
  links; source files themselves remain in the generated-program repository.
- Compact evidence for the one observed nondeterministic Cahn-Hilliard validation.
- Source-pinned supplemental external-validation cases and dispositions, including
  bounded execution logs and build receipts for targeted correctness checks.
  Earlier passes and timings remain immutable when current eligibility changes.
  Complete numerical failure arrays and small reviewed replica ambiguities are
  retained as scalar-byte witnesses, deduplicated by SHA-256. Successful bulk
  arrays are omitted; their observations and comparisons remain bound to the
  source, executable and exact validation method.
- The final pipeline source snapshot named by the last amendment.
- Compact reported Codex usage with session/run identity, counters, original terminal
  counter, and transcript/session hashes. Delegated runs retain unique-request totals
  across parent and child sessions, with interrupted-request uncertainty explicitly
  flagged. Recovery code is retained separately from the immutable measurement pipeline.
- Compact exact OpenCode request/session accounting, retry-excluded elapsed time,
  metadata hashes and pricing-context checks. Identical effective configuration is
  retained once and hash-linked from each observation; original transcripts and
  native event/session exports remain in the generated-program repository.
- Analysis code, environment locks, final tables, and one canonical representation of
  each final figure.
- The authored winner-audit counterexample wrapper, retained as analysis source
  to reproduce validator blind spots; it includes separately retained input code
  rather than duplicating that code. Generated program sources remain excluded.

## Excluded

- LLM-generated or sequential benchmark source code already stored in their own
  repositories.
- Staged source snapshots, executables, libraries, objects, compiler output, CMake and
  Make build trees, caches, core files, and temporary workspaces.
- Successful benchmark stdout/command logs; parsed metrics, arguments, execution state,
  and wall times are retained in structured metadata.
- Raw calibration logs duplicated by the complete proposal and manual-review summaries.
- Per-ID YAML fragments after their fields have been normalized into JSONL.
- Raw agent event streams, per-program prompt transcripts, and hundreds of individual
  review files after their decisions and evidence have been normalized into compact
  JSONL summaries.
- Archived pre-correction benchmark log trees for the 587 timing reruns. The prior Git
  release and compact comparison JSONL preserve their observations without duplicating
  successful logs.
- Unrelated records from interrupted or invalidated full-corpus runs.
- Notebook cell output, analysis caches, and intermediate datasets reproducible from
  the canonical CSV/JSONL inputs.

## Versioning and corrections

`main` contains one current canonical snapshot. Annotated Git tags identify immutable
releases; tags do not require dated copies of the complete tree.
Additional independent campaigns are retained once under `batches/`. `release/`
is the current joined/scored view; historical `data/` records remain immutable.
Small campaign method deltas refer to already retained files instead of duplicating
another full pipeline snapshot. Nested campaign checksums and the root checksum
manifest are regenerated together by `tools/update_checksums.rb`.

A localized correction changes only its affected record partition and evidence plus
the regenerated aggregate/scoring files. It must include amendment provenance, direct
links to both source revisions, and a generated guard proving unrelated records are
unchanged. A new
full-corpus snapshot is accepted only for a systemic issue affecting the corpus as a
whole.

## Enforced budgets

- curated `data/`: at most 60 MiB;
- `analysis/`: at most 20 MiB;
- complete scientific artifact tree (excluding the website): at most 640 MiB;
- individual file: at most 10 MiB.

Git LFS is not used. Any exception requires an explicit policy change and must explain
why the additional artifact is scientifically necessary.

The tree budget accommodates retained campaigns, timing audits, corrections and
scoped rerun evidence, and complete supplemental correctness sweeps with retained
outputs and provenance. The per-file, historical `data/`, and analysis budgets remain
separate constraints. Binaries, duplicate program sources and raw agent streams
are excluded. Historical QT replacements are a scoped overlay under `corrections/`;
their prior observations remain in the immutable source campaigns.
The complete-array sweep contributes about 96 MB for 6,747 checked programs,
including complete failure witnesses and source-bound observer reviews. This
evidence is required to audit the exclusions; successful bulk arrays are not retained.
