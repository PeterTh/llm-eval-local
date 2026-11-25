# `roomsim_gpt-6.2-astra-medium_mpi_r3`

Date: 2026-11-25

## Scope

MPI Roomsim, 5,120 triangles and 500 steps on 128 ranks. Median: 4,326 ms.

## Finding

Ranks own contiguous receiver rows and preserve their segment of the reference
random stream using a prefix count and `mt19937::discard`. Dense local weights
and delays feed propagation, with a ring buffer for recent remote radiosity,
an all-gather each step, and complete local histories for correlation.

## Close-group comparison

This is the row-distributed family described in the
[Opus 5.5 review](roomsim_claude-opus-5.5-cc-medium_mpi_r1.md), with different
random-stream and storage choices. The nominal lead over its 4,386 ms median is
only 1.4%. The new 4,270–4,464 ms range contains the predecessor's 4,362–4,399 ms
range; Astra r4 and Sol r5 also sit nearby at 4,329 and 4,345 ms.

## Correctness and timing

Complete-array validation and corrected-source revalidation passed. The corrected
timer covers preprocessing, propagation and distance gathering, reporting the
maximum complete rank interval.

## Interpretation

A nominal new leader in a close group, not evidence that its dense storage or
random-stream handling is independently superior.
