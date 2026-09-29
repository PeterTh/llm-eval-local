# Timing-correction pilot quality gate — 2026-09-28

All 16 stratified Sol/high proposals are materializable and compile successfully
with the pinned GCC13/CUDA12.6 toolchain. The pilot covers all 11 benchmarks, all
three models and both backends. No generated program was executed by proposal
workers or by the compile-only materializer. Original source remains unchanged.

The main investigator read every exact old/new replacement and inspected the
surrounding original timer and rank-control path. Every added timing collective
is reached by all communicator ranks after a complete local interval; root-only
printing follows the collective. MPI_LONG is paired with actual long variables
(or the compile-proven chrono count), and MPI_DOUBLE with double variables.
The edits preserve computation, partitioning, inputs, iteration counts, reference
validation and result collection. Rate calculations use the corrected duration.

Representative source checks (original pinned source line numbers):

| Pilot program | Source-grounded check |
| --- | --- |
| nbody Fable hybrid r1 | Blocking device copies and allgather precede stop; reduction after lines 300–302, output 304–305. |
| cahn-hilliard Sonnet MPI r2 | Complete halo/chemical/update loop, stop 286–288; existing durationMs consumers become global. |
| black-scholes Fable MPI r2 | Local pricing 214–216, stop 218–220; double maximum, millisecond output and throughput agree. |
| roomsim Fable hybrid r1 | Complete sequential phase intervals 1247–1284; per-phase MPI_MAX values summed at original 1291–1295. GPU completion in called routines (922, 968–980, 1019). |
| floydwarshall Opus hybrid r5 | Both streams synchronized at 706–707, stop 709–712; reduction precedes canonical output and GOPS. |
| qtclustering Sonnet MPI r4 | Full clustering call 398, stop 400–403; added reduction outside rank conditional; both output/rates updated. |
| matmul Opus hybrid r1 | Completed matrixMultiply and unchanged gather 712–724; worker stream completion at 457; reduction after complete local stop. |
| stencil3d Sonnet MPI r1 | All halo/stencil iterations 230–236, stop 238–240; output and MCellUpdates/s share maximum. |
| unstructured Opus hybrid r5 | Called routine synchronizes streams 354–356; stop 545–547; reduction does not move untimed state collection. |
| spmv Fable MPI r3 | All requested iterations 316–319, stop 321–323; gather stays outside timing; canonical and rate outputs corrected. |
| cholesky Sonnet hybrid r5 | Complete decomposition, device synchronization at 267 and world stop 409–411; reduction before existing failure/print handling. |
| cahn-hilliard Fable MPI r2 | All outstanding halo requests completed, local work and final barrier precede elapsed value 292–293; double maximum. |
| nbody Opus hybrid r5 | Final device synchronization 378 and stop 379–382; long maximum before root print. |
| black-scholes Sonnet MPI r2 | All local pricing and stop 216–218 retained; double milliseconds improve only timing precision; gathering unchanged. |
| roomsim Opus MPI r1 | Three complete local phase intervals 1218–1253 summed locally, then MPI_MAX of complete per-rank totals at 1258–1260. |
| spmv Fable hybrid r4 | All CUDA iterations 399–403 and device completion 405 precede stop 408–409; result-copy region remains untimed. |

RoomSim proposals use either the maximum of complete local totals or a sum of
correctly measured maxima for sequential phases. Both are covered by the existing
review contract; no algorithm or phase boundaries are changed. Existing auxiliary
rank-local phase printouts are not automatically rewritten when only the canonical
total requires repair; independent review must check the canonical total explicitly.

Expansion is approved for proposal generation only. Every complete corrected source
still requires independent post-fix review, with stronger adjudication of disputed
or uncertain cases, followed by affected-program validation before acceptance.
The two conditional Floyd-Warshall cases are absent from the correction inventory.

Tooling tests: 103 tests, 750 assertions, zero failures/errors, three expected skips.
Resumed attempts receive new directories and verified source/response/event bindings.
