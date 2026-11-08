# `cholesky_claude-fable-5.1-cc-medium_hybrid_r4`

Date: 2026-11-08

## Scope

Hybrid Cholesky, N=4,096, four GPUs. The median is 41 ms, versus 50 ms for
Fable r1 and 56 ms for the previous Opus 5.5 winner.

## Finding

The matrix is distributed in cyclic 128-row blocks, eight per rank. Custom
double-precision GPU kernels perform the entire factorization, including the
64-wide diagonal subblocks and their triangular inverses. Multiplication by
those inverses turns panel solves into matrix products. Lower-triangular trailing
updates avoid computing unused upper blocks.

Two-column lookahead separates the dependency-critical path from bulk updates.
A high-priority stream updates upcoming panels, a second performs the remaining
matrix updates, and a third uploads panel data. Node-shared, page-locked MPI
windows avoid interprocess messages for local panel exchange; only remote-node
leaders receive messages. This is a genuinely distributed factorization, not
four independent replicas.

An important boundary distinction accompanies the fast kernels: the timed result
is the completed, distributed GPU factor. Copying its rows back and assembling
the full host matrix happen only for output or validation, after timing.

## Close-group comparison

The [previous winner](cholesky_claude-opus-5.5-cc-medium_hybrid_r1.md) already uses
custom kernels, 128-wide cyclic columns, shared transfers and lookahead, but does
its small diagonal factorization on the CPU and assembles the host result during
the factorization. Its 55–57 ms samples and Fable's 41–42 ms samples are well
separated. Fable r1, at 47–52 ms, is a closer architectural peer: GPU diagonal
work, cyclic rows, lookahead and post-timer result collection.

A [limited diagnostic](../2026-11-08-fable51-outlier-probes.json) forced r4's
otherwise optional host collection without changing its decomposition. Three
post-warm-up samples took 40, 41 and 40 ms for decomposition, then 351.7, 349.8
and 354.7 ms for collection. This is not a matched host-result comparison with
Opus, whose assembly overlaps computation. It shows why the 26.8% published
median reduction cannot be interpreted as an end-to-end host-result speedup.
The diagnostic samples do not replace the benchmark data.

## Correctness and timing

Native validation, shape/topology checks and full-array comparison passed.
Root starts before factoring block zero, and that factorization gates all other
ranks' useful work. Every GPU finishes its streams and final upper-triangle
zeroing before the closing world barrier. Root's interval therefore encloses
the distributed computation even without an elapsed-time maximum reduction.
No timing correction was needed.

## Interpretation

A strong compute-only result, with a meaningful 18% lead even over Fable r1's
similar result-residency design. GPU scheduling and kernel/layout differences
are plausible contributors; they have not been isolated individually. The host
collection policy is a material comparability caveat, not unfinished GPU work
hidden beyond the timer.
