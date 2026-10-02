# `qtclustering_claude-opus-5-cc-medium_mpi_r5`

Date: 2026-10-02

## Scope

MPI QT clustering, 4,000 points. The median is 12 ms. This led the Claude release
but is fifth after the pending Astra 6 results at 9, 10, 10 and 10 ms.

## Finding

Cyclic seed ownership, incremental maximum distances and cached candidate
memberships avoid repeating unaffected growth work. A cached candidate remains
usable until a committed cluster removes one of its members. Maximum-location
selection and membership broadcast coordinate each global choice.

## Close-group comparison

The [Astra winner](qtclustering_gpt-6-astra-medium_mpi_r5.md) uses
the same broad idea but precomputes sparse threshold neighborhoods. This Opus
implementation scans the full point set when rebuilding the initial neighborhood.
That is a plausible source of the group difference; its 10–13 ms range also
overlaps several of the new results. The
[older Sol review](qtclustering_gpt-5.6-sol-xhigh_mpi_r2.md) gives the earlier
distributed-clustering context.

## Correctness and timing

Retained validation passed. Neighborhood construction and all greedy rounds are
included, with synchronized timing and a maximum-rank report. The
[retained QT checks](../2026-09-29-qt-winner-correctness.json) match the sequential
reference at N=1,200 and the other Claude winners at the benchmark sizes; they do
not constitute a full-size sequential proof.

## Interpretation

A fast incremental implementation, now part of a close leading group rather than
an isolated winner.
