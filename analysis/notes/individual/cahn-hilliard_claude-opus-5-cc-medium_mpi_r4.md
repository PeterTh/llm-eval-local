# `cahn-hilliard_claude-opus-5-cc-medium_mpi_r4`

Date: 2026-10-02

## Scope

MPI Cahn–Hilliard, a 256³ grid for 2,000 steps. The median is 1,384 ms, versus
1,409 ms for Luna 5.6 xhigh r2 and 1,427 ms for Opus r3.

## Finding

A two-dimensional Y/Z process grid leaves X rows contiguous. Nonblocking halo
transfers overlap interior updates, followed by boundary work after the necessary
faces arrive. Both chemical-potential and concentration stages retain their halo
dependencies.

## Close-group comparison

The [Luna review](cahn-hilliard_gpt-5.6-luna-xhigh_mpi_r2.md) describes a related
overlap strategy, but with a three-dimensional decomposition, manually packed faces
and persistent requests. Opus r3 also uses a three-dimensional decomposition.
The 1.8% lead over Luna is small, although their retained ranges, 1,377–1,391 and
1,404–1,418 ms, do not overlap. These are different halo-layout choices within the
same two-stage stencil algorithm.

## Correctness and timing

Retained validation passed. Every step completes both stencil stages and their
required exchanges; the reported interval uses the maximum across ranks.

## Interpretation

A modest layout/communication improvement within an already fast MPI group, not
evidence that a two-dimensional process grid is generally superior.
