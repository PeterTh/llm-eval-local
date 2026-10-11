# `black-scholes_gpt-6.1-sol-xhigh_mpi_r5`

Date: 2026-10-11

## Scope

MPI Black–Scholes, 10 million options on 128 ranks. The median is 7.646 ms,
2.2% below the previous best at 7.818 ms.

## Finding

Ranks generate their own contiguous option ranges from global indices, avoiding
an input scatter. Seven sets of invariant pricing terms are prepared once, but
each option still evaluates the full scaled formula, including its logarithm
and error functions. This is not the seven-price reuse shortcut seen in some
GPU implementations.

## Close-group comparison

The 7.568–7.691 ms samples overlap those of the
[previous Qwen leader](black-scholes_qwen-3.6-27B-udq4_mpi_r5.md),
which scatters options and uses a scalar pricing loop. Other leading medians
remain around 7.85–7.93 ms. Local input generation and invariant-term reuse
distinguish this implementation, but these five samples do not establish their
individual contribution to the small lead.

## Correctness and timing

Native validation and static timing review passed without correction. A starting
barrier precedes local option generation and pricing; `MPI_MAX` selects the
complete per-rank elapsed time. Result gathering follows the timed computation.

## Interpretation

A new member of the existing fast scalar-pricing group, not a separated outlier.
