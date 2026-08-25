# `unstructured_gpt-5.6-sol-low_hybrid_r5`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `unstructured` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 7,000 by 7,000
element grid for 4,000 iterations on four ranks and four GPUs. Its five times are
2181.128, 2177.494, 2181.516, 2176.701, and 2178.706 ms, with a 2178.706 ms median.
The runner-up median is 2198.081 ms.

## Finding

The regular grid is split into one-dimensional row slabs with two ghost rows. Each
rank keeps separate energy and total-flux ping-pong arrays on its GPU and uses a
32 x 8 two-dimensional kernel. Pinned host buffers stage halo rows. The implementation
posts nonblocking receives and sends to both neighbors together, computes the deep
interior while the exchange is in flight, installs the received rows, and then
finishes the two halo-dependent edge rows.

## Close-group comparison

The 2198.081 ms runner-up has the same overall solution shape: row slabs, two ghost
rows, separate ping-pong fields, the same 32 x 8 GPU work layout, pinned staging, and
interior/edge overlap. Its primary communication distinction is two sequential
`MPI_Sendrecv` operations rather than posting both neighbor directions together.

The median difference is 0.9%, and both implementations are extremely stable. The
winner's fully concurrent neighbor exchange is a plausible small advantage, but the
results remain a practical tie using the same distributed and GPU-local algorithm.
They do not represent independent approaches converging by coincidence.

## Correctness and timing validity

All rows and all 4,000 iterations are computed. Halo arrival is required before edge
updates and before the next state is consumed. GPU work is synchronized, and maximum
rank time is reported for the distributed interval. Retained internal validation and
external output comparison passed.

## Interpretation

This is a close-group first place. It modestly favors posting both neighbor exchanges
together, but the stronger conclusion is that both leading runs implement the same
effective overlap pattern.

## Non-decisions

- No generated source or benchmark result is changed.
- No alternate measurement replaces the retained score.
