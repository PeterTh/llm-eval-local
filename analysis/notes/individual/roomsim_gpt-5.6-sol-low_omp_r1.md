# `roomsim_gpt-5.6-sol-low_omp_r1`

Date: 2026-08-25

Status: verified performance explanation; valid under the retained approximate-output contract

## Scope

This note explains the first-place outlier in the `roomsim` OpenMP cell for
data release `local-eval-2026-08-25` at data commit `f83773e`.

The retained benchmark used 5,120 triangles and 500 time steps on 128 physical
cores. Its total computation times are 2,263, 2,256, 2,250, 2,252, and
2,255 ms, giving a median of 2,255 ms. The next result has a 4,038 ms median,
so this run is 1.79x faster.

## Finding

The implementation computes each unordered form-factor pair once and mirrors
the result, almost halving the benchmark's dominant precomputation.

For triangles i and j, the sampled geometric kernel is
`cos(i) * cos(j) / (pi * distance^2)`, subject to visibility of the same
line segment. Exchanging i and j reverses the segment and both normal
directions, leaving the exact geometric quantity unchanged. Time delay is also
symmetric.

The reference implementation evaluates both ordered directions independently,
using separate Monte Carlo samples. This implementation instead draws one
16-ray estimate for the unordered pair and assigns that estimate to both
directions. It then computes only the upper triangle of the time-delay matrix
and mirrors that exact value.

This is not a bit-for-bit preservation of the reference random stream. It is
an exploitation of mathematical reciprocity: each direction receives an
unbiased estimate of the same reciprocal quantity, but the two estimates are
now correlated.

## Controlled evidence

The retained phase measurements locate the complete advantage in
precomputation. This run spends 1,857-1,867 ms in precomputation; the runner-up
spends 3,716-3,721 ms. The winner is actually slower in the later simulation
and distance phases, so those phases cannot explain first place.

A temporary variant changed only the form-factor loop back to evaluating every
ordered non-diagonal pair. The reciprocal original took 1,851-1,853 ms in
precomputation and 2,243-2,251 ms total. The directional variant took
3,731-3,750 ms in precomputation and 4,127-4,145 ms total. The near-exact
doubled precomputation identifies the mirrored Monte Carlo calculation as the
cause of the retained gap.

## Correctness and timing validity

The exact geometric integrand, segment visibility, and delay are reciprocal.
The optimization changes which random samples estimate that reciprocal value,
not the physical formula or the number of rays in either reported direction.
Because this benchmark validates approximate derived distances rather than an
exact random-number trajectory, that distinction is governed by its output
tolerance.

The retained run passed internal validation and external output comparison
against the reference. Its result did not have an exact reference hash, which
is expected for this stochastic rearrangement. The validation outcome is the
evidence that the changed estimator remains within the established contract;
it should not be described as bitwise equivalence.

The reported total is the sum of separately timed precomputation, simulation,
and distance phases. Each OpenMP worksharing region completes before its phase
timer stops. No asynchronous work or omitted phase explains the value.

## Interpretation

This is a valid algorithmic outlier under the retained approximate-output
contract. It is qualitatively different from a pure cache optimization:
performance comes from enforcing exact physical reciprocity on a stochastic
estimator and thereby correlating the two directional estimates. Analyses that
require preservation of the reference random stream should keep that caveat,
even though the evaluated output comparison passed.

## Non-decisions

- No validation result, benchmark measurement, tolerance, or score is changed.
- No generated source is changed.
- The directional temporary variant is explanatory evidence, not replacement
  benchmark data.
