# `roomsim_claude-opus-5.5-cc-medium_mpi_r1`

Date: 2026-10-06

## Scope

MPI Roomsim, 5,120 triangles and 500 steps. The median is 4,386 ms, beside
4,424 ms for Opus 5.5 r4 and 4,449 ms for the previous Terra winner.

## Finding

Receiver rows are distributed using a sampled ray-traversal cost estimate.
Jump-ahead preserves each rank's segment of the sequential random stream, local
form factors are stored in compressed form, and propagation all-gathers the
radiosity vector after each step.

## Close-group comparison

This remains the row-distributed family described in the
[Terra review](roomsim_gpt-5.6-terra-xhigh_mpi_r2.md). The nominal 1.4% improvement
over that result is small relative to the group's variation: r4 spans
4,336–4,727 ms and Terra spans 4,406–4,961 ms, versus 4,362–4,399 ms here.
The samples do not establish that sampled load balancing or compressed storage
causes the small ordering.

## Correctness and timing

Validation and corrected-source revalidation passed. All three computational
phases complete their required collectives. The corrected total is the maximum
across ranks of each rank's summed phase durations.

## Interpretation

A nominal new leader in an already close MPI group, not an isolated performance
breakthrough.
