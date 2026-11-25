# `black-scholes_gpt-6.2-sol-medium_mpi_r5`

Date: 2026-11-25

## Scope

MPI Black–Scholes, ten million options on 128 ranks. The 1.742 ms median is
77.2% below the previous leader's 7.646 ms; their sample ranges do not overlap.

## Finding

The seven option templates repeat with a common scaling of spot and strike.
Rather than evaluating logarithms and normal CDFs for every option, each rank
keeps eight cached CDF pairs per template. The key is the actual floating-point
ratio of the scaled prices, checked for exact equality before reuse. This
preserves rounding differences that a simple scaled-base-price shortcut could
lose. A miss evaluates the original logarithm and two CDFs inside the timer.

Every rank still visits every owned option and computes its scaled price. Without
output flags, prices are accumulated into an observable volatile sum instead of
materializing a full result array. With `-r`, all prices are retained and gathered.

## Close-group comparison

The [Sol 6.1 XHigh leader](black-scholes_gpt-6.1-sol-xhigh_mpi_r5.md) also factors
out fixed template terms, but retains the expensive per-option formula. Astra
6.2 r1, at 7.373 ms, joins that older 7–8 ms group; Sol r5 is clearly separate.

A [paired diagnostic](../2026-11-25-gpt62-outlier-probes.json) disabled only cache
reuse in a temporary copy, keeping the same output handling and fixed setup.
After one warm-up per mode, the three-sample medians were 1.707 ms with caching
and 8.787 ms without it. The 5.1× ratio identifies coefficient reuse as sufficient
to explain the observed separation. These short diagnostic intervals are not
replacement benchmark samples.

## Correctness and timing

External validation, complete-array comparison and timing review passed.
The paired diagnostic also produced identical result blocks at 1,031 options.
A starting barrier and maximum-rank reduction cover the full pricing loop.
Small fixed-size template setup remains outside timing under the shared policy;
cache population and all input-size-dependent pricing remain inside.

## Interpretation

A substantial, valid optimization of the benchmark's repeated-template workload,
not evidence of the same speedup on independently varying financial inputs.
