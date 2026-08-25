# Timing-correction impact

This report is generated from the versioned timing audit, scoped-rerun comparison,
and final scored dataset. It analyzes only the 587 programs whose static timing
review required a timing-only source correction; it does not reinterpret validation.

- Corrected benchmark successes: 587/587
- Corrected benchmark failures: 0
- Comparable old/new median timings: 587
- Median corrected/original reported-time ratio: 1.00013
- Scores changed after corrected timing: 43/587
- Score increases / decreases: 31 / 12
- Audited MPI/hybrid scores changed after re-thresholding: 111/1,615
  (43 timing-fixed,
  68 unchanged-source programs)
- Corrected medians below 200 ms: 39/587
- Corrected runs with median wall time over 10x reported compute time: 102/587

The ratio is descriptive, not a correction factor: the original value can be a
rank-local duration and therefore need not have a stable mathematical relationship
to the corrected maximum completed-rank duration. See
`tables/timing-correction-summary.csv` for benchmark/backend/model groupings,
`tables/timing-correction-details.csv` for per-program source links and score
changes, `tables/timing-audit-score-changes.csv` for every score affected by the
corrected cell distributions, and `tables/timing-correction-issue-counts.csv` for
issue categories.

The detail table retains repetition-spread and wall-to-reported-time ratios. These
expose short or setup-dominated measurements—most visibly some Black-Scholes MPI
programs—whose fine ordering should not be overinterpreted. Scoring boundaries
use a per-cell repetition-noise floor, so those observations remain grouped unless
an adjacent performance gap exceeds the measured noise.

Most frequent static issue category: rank_local_timing
(577 records).
