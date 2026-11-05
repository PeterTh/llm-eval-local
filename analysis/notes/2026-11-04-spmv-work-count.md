# SpMV repetition and work coverage review

All 722 SpMV implementations still eligible after supplemental validation were
reviewed for omitted repetitions, rows or stored nonzeros. No new work-count
omission was identified. Eligibility, scores and performance measurements are
unchanged; no program was executed or modified during this static phase.

SpMV repeatedly computes the same immutable matrix–vector product, so even a
complete final-vector comparison cannot establish the number of repetitions.
The review therefore followed runtime iteration bounds, MPI partition coverage,
CPU worker loops, CUDA launch/graph counts and remainder paths, and row/nonzero
arithmetic through result stores. It inspected pinned sources/build settings
and their bound validation executables, not just final numerical output.

## Coverage and checks

The 12-program pilot was reused, followed by 710 additional inspections. After
a checked six-case delegation pilot, up to three Luna reviewers handled disjoint
assignments. Primary review checked every reported finding and evidence claim,
independently inspected at least one case per batch and additional suspicious
paths, and required corrections for wrong addresses, incomplete callees and
duplicate or missing IDs. Only four semantically uncertain library/JIT cases
went to Sol-6.1. All were resolved without a work-count exclusion.

The [completion receipt](../../validation-supplements/20261104-spmv-work-count-full/completion.json), verified
at 16:27:49 UTC on 4 November 2026, accounts for every ID and binds all 710 new
review records. The [pilot](2026-11-04-spmv-work-count-pilot/review.json) remains
a separate, digest-checked dependency. Raw proposals are not accepted verdicts;
the per-ID records identify their checked input and primary corrections.

This is a static review, not a proof for arbitrary inputs or compilers. Historical
performance binaries were not assumed identical to the validation binaries.
Three cuSPARSE cases were checked at the library API contract boundary; vendor
device instructions were not inspected. Where only older-architecture CUDA code
was embedded, the retained PTX supplied device-level evidence, without asserting
inspection of the runtime JIT machine code. Early immutable records preserve
missing compilation-counter metadata explicitly, and agent-reported inspection
intervals are not used for cost or throughput estimates.

## Retained implementation concerns

Per-ID evidence retains limitations that are not demonstrated failures under
the reviewed workload. These include extra full-matrix work, idle-rank/empty
partition edge cases, CPU execution under a CUDA/hybrid label, and a capped CUDA
grid without a row grid-stride loop. For example,
[Qwen3.6 pi-t CUDA r4](../../validation-supplements/20261104-spmv-work-count-full/reviews/spmv_qwen-3.6-27B-udq4-pi-t_cuda_r4.json)
covers at most 16,776,960 rows with that grid, while its archived benchmark uses
10,000 rows. Such concerns remain visible without being converted into unsupported
scientific exclusions.

The subsequent [complete-array sweep](2026-11-04-full-array-validation.md)
confirmed the previously noted uneven-`MPI_Gather` concern in
`spmv_gpt-4.1_mpi_r4` as an external-validation execution failure. That later
runtime finding does not change this static phase's work-count verdict.

## Retention and reproduction

The [export receipt](../../validation-supplements/20261104-spmv-work-count-full/export.json) binds 2,411 JSON
files totalling 68,158,101 bytes excluding the receipt. They retain source and
executable provenance, selected compiled excerpts, exact accepted review inputs
and raw delegated reports. Generated source trees, binaries and complete dumps
are excluded. The original programs remain in their Git repository.

The experiment repository's `tools/validation_audit/README.md` documents the
`spmv_full_review.rb verify` and `export_spmv_full.rb` commands. Their exact method
hashes are in [method-files.json](../../validation-supplements/20261104-spmv-work-count-full/method-files.json).
Verification checks provenance and evidence integrity; it does not automatically
reproduce the scientific judgments.
