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
- The final pipeline source snapshot named by the last amendment.
- Compact exact reported Codex usage with session/run identity, cumulative counters,
  original terminal counter, and transcript/session hashes; recovery code is retained
  separately from the immutable measurement pipeline snapshot.
- Analysis code, environment locks, final tables, and one canonical representation of
  each final figure.

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
- complete scientific artifact tree (excluding the website): at most 150 MiB;
- individual file: at most 10 MiB.

Git LFS is not used. Any exception requires an explicit policy change and must explain
why the additional artifact is scientifically necessary.

The tree cap was increased from 100 to 150 MiB with user approval on 2026-10-02
for the additional GPT-6 campaign, all-backend QT timing audit, shared corrections,
and scoped rerun evidence. Per-file, historical `data/`, and analysis caps are
unchanged. This does not authorize binaries, duplicate program sources or raw
agent streams. Historical QT replacements are a scoped overlay under `corrections/`;
their prior observations remain in the immutable source campaigns.
