# Astra and Sol 6.2 Medium

This campaign contains 440 Codex-generated programs: 220 per profile. Astra
passes validation in all 220 cases; Sol passes in 219. All 439 eligible programs
have successful measurements using the established sizes, resource profiles,
one warm-up and five samples. `cholesky_gpt-6.2-sol-medium_cuda_r4` retains its
original build failure; it was not repaired or retried.

## Validation and timing

Validation includes shape/topology and boundary-sensitive cases, applicable
complete-array comparisons, and static SpMV work-count review for all 40 SpMV
programs. The timing review covers 240 unique MPI/hybrid or QT implementations:
216 are valid without changes and 24 have accepted timing-only corrections.
All 24 corrected versions passed revalidation with unchanged numerical result
blocks. Small fixed-size Black–Scholes template setup follows the shared timing
policy; input-size-dependent work remains timed.

Original code is preserved at generated-source commit
`7a0a8b8e28af48d4ee2525c13ced317726536b25`; the single timing-correction commit is
`1e10bfb901d02f49780de336995fef5b0bf8f5c8`. The
[correction registry](timing-corrections/README.md) exposes both revisions.
The [resolved audit selection](timing-audit/resolved-selection.json) records
which decisions govern the corrections while retaining earlier findings.

## Retained evidence

- `validation/`: source-bound outcomes, exact correctness output and observer evidence;
- `validation/spmv-work-count/`: all accepted reviews, checked pilot/full proposals and compact compiled excerpts;
- `timing-audit/` and `timing-corrections/`: static findings, patches, independent review and revalidation;
- `benchmark/`: all 439 five-sample measurement records and frozen configurations;
- `generation/`: exact native usage, compact request accounting, frozen Standard prices and deduplicated harness method;
- `provenance/observer-continuations/`: observer compatibility receipts and five deduplicated method layouts;
- `completion/`: completion gates and compact-export verification.

The original generated programs and transcripts remain in their source repository.
Binaries, build trees, captured numerical array dumps and complete disassembly
are excluded. Observer compatibility continuations reused completed validation
records; they did not restart the campaign or repeat performance measurements.

The combined release adds nine cell winners, each with an
[individual review](../../analysis/notes/2026-11-25-gpt62-medium-winner-context.json).
Two limited temporary ablations explain caching and pruning outliers; those
diagnostics do not replace benchmark samples. All prior observations are preserved
apart from the established joint-scoring threshold update.
