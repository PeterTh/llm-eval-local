# Pilot quality review — 2026-09-28

Source commit: `db27e2872a28b900024d318f6a3004a3a7fddfa7`.
The main agent statically inspected all 16 pilot timer paths, their called
computation functions, canonical output variables, MPI duration datatypes, and
device-completion dependencies. No generated program was executed for this audit.

## Outcome and expansion gate

The primary Luna/high pilot produced six valid and ten invalid decisions, all high
confidence. All six MPI_MAX cases have complete local timed computation, correct
aggregation/output units, and (for hybrid cases) completed device work. Seven
root-local cases lack a global start dependency. Three flagged cases instead have
source-proven root-controlled work-start dependencies and globally enclosing stops.

| Program (batch-relative ID) | Main-agent source check |
| --- | --- |
| matmul_claude-sonnet-5-cc-medium_hybrid_r3 | Valid: blocking D2H after cuBLAS, double/MPI_DOUBLE maximum, printed milliseconds (213–278). |
| unstructured_claude-fable-5-cc-medium_mpi_r5 | Invalid: independent halo packing/interior updates can precede root start (181–248); root-only duration (391–421). |
| qtclustering_claude-opus-5-cc-medium_mpi_r3 | Invalid: independent neighbor/grid work precedes collectives (348–438); root-only duration (667–682). |
| nbody_claude-fable-5-cc-medium_hybrid_r1 | Invalid: independent kernels precede the allgather; completed GPU work but unaggregated root time (280–305). |
| cholesky_claude-opus-5-cc-medium_mpi_r4 | Global-makespan equivalence: rank 0 owns and factors the first panel, gating dependent work through column/row broadcasts (319–414, 721–724); world stop barrier (772–790). |
| floydwarshall_claude-sonnet-5-cc-medium_hybrid_r1 | Global-makespan equivalence: rank 0 owns the first pivot, gating every first update via Bcast (185–217); synchronized streams and final barrier precede root stop (217–246). |
| cahn-hilliard_claude-fable-5-cc-medium_mpi_r2 | Invalid: independent halo/interior work, no elapsed-time aggregation (251–296). |
| black-scholes_claude-sonnet-5-cc-medium_hybrid_r1 | Valid: stream synchronization and OpenMP join before local stop (251–288), double/MPI_DOUBLE maximum and canonical output (352–386). |
| stencil3d_claude-opus-5-cc-medium_mpi_r1 | Invalid: local stencil work can precede root start; root-only elapsed time (390–489). |
| spmv_claude-opus-5-cc-medium_hybrid_r3 | Valid: warmup excluded; full iterations, device sync, then double/MPI_DOUBLE maximum (498–531). |
| roomsim_claude-fable-5-cc-medium_mpi_r4 | Invalid: three independent local phase timers summed only on root (949–995); phase maxima would be a timing-only repair. |
| cahn-hilliard_claude-sonnet-5-cc-medium_hybrid_r2 | Valid: all iterations and device sync precede local stop; long long/MPI_LONG_LONG maximum is printed (332–362). |
| floydwarshall_claude-fable-5-cc-medium_hybrid_r5 | Global-makespan equivalence: root-timed Scatterv gates required input (95–101); device sync, gathers, and final barrier enclose completion (142–157, 279–292). |
| matmul_claude-sonnet-5-cc-medium_mpi_r4 | Valid: full row computation, double/MPI_DOUBLE maximum, canonical milliseconds (160–196). |
| unstructured_claude-opus-5-cc-medium_hybrid_r3 | Valid: stream dependencies and final compute-stream sync complete GPU work (449–508); int64_t/MPI_INT64_T maximum (701–712). |
| nbody_claude-sonnet-5-cc-medium_mpi_r5 | Invalid: independent force/integration work precedes allgather; root-only duration (218–233). |

Line numbers refer to each program's benchmark source in the pinned Git tree.

## Review refinement

The original prompt caused both Luna and three blind Sol/xhigh checks to over-focus
on the generic barrier/local-timer pattern. Merely upgrading the model did not
resolve that weakness. The source proofs above distinguish useful computation from
setup, dispatch bookkeeping, or waiting before a root-issued dependency; the timing
contract already permits initialization outside a compute-only timed region.

Independent-review guidance now explicitly requires tracing the first useful work
and root-issued scatter/first-pivot/first-panel dependencies. This is not a blanket
acceptance of Bcast/Scatter: independent numerical or halo work before the dependency
still invalidates a root-local interval. No previous verdict or case-specific proof
is included in an investigator's prompt.

A five-case blind Luna/high check with this guidance classified all three
root-controlled cases valid and both controls (N-body MPI and Unstructured MPI)
invalid, matching the source inspection. Original and refined findings are retained
in separate pilot audit directories; they have not silently overwritten each other.

**Expansion approved for the full multi-stage method, not for primary verdicts
alone.** Every primary invalid/ambiguous/non-high-confidence result and every valid
result without lexical MPI_MAX gets the refined independent review. Disagreements,
category/fixability differences, and unresolved uncertainty get blind Sol/xhigh
adjudication using the same refined guidance. Final ambiguity remains explicit.

## Operational checks

Shell execution, web search, hooks, and external integrations are disabled; all
accepted event streams contain no tool calls. A startup diagnostic confirming the
disabled code-mode host was initially mistaken for tool use. The checker was fixed,
eight completed responses were recovered without new calls, and the eight pending
pilot cases were completed. Initial manifests, runner snapshot, original attempt
metadata, duplicate/unused-attempt usage, recovery procedure, and response hashes are
retained under `recovery/`. One malformed initial response was skipped, not edited.

Full test suite after the review refinement: 99 tests, 714 assertions, zero failures,
zero errors, three expected skips. Validation was not rerun; generated sources,
benchmark parameters, and the historical scored release remain unchanged.
