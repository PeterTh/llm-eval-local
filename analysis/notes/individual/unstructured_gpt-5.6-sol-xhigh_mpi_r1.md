# `unstructured_gpt-5.6-sol-xhigh_mpi_r1`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place MPI result in the `unstructured` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 2,000 by 2,000
element grid for 5,000 iterations on 128 ranks. Its times are 323.088, 318.661,
321.655, 332.347, and 335.374 ms, giving a 323.088 ms median. The runner-up median is
326 ms.

## Finding

The implementation maps the regular topology onto a two-dimensional Cartesian
process grid. Ranks store ghost rows and columns, use structure-of-arrays energy
buffers in ping-pong form, and keep one total-flux array updated in place. Persistent
MPI requests and derived column datatypes reduce halo setup and packing overhead.
Each iteration exchanges faces, computes the independent core, then completes the
perimeter after communication.

This is a compact state representation paired with the standard low-surface-area,
overlapped two-dimensional decomposition.

## Close-group comparison

The 326 ms runner-up uses the same two-dimensional Cartesian layout, persistent halo
communication, derived column handling, and core/perimeter overlap. Its main state
difference is ping-pong storage for total flux as well as energy, giving four dynamic
arrays rather than the winner's three; ghost representation and shell loop details
also differ.

The medians differ by 0.9%, and the sample ranges overlap widely. These two results
are a practical tie with the same solution shape. A third related implementation at
364.725 ms is about 13% slower but still uses a broadly similar Cartesian decomposition,
so the exact leader reflects implementation details rather than a unique algorithm.

## Correctness and timing validity

Every process-owned element is updated in all iterations, and halo-dependent cells
wait for the corresponding exchanges. In-place total-flux storage is safe because the
next energy update consumes the completed flux field, not partially updated values.
Barriers delimit the interval and maximum-rank timing reports the distributed critical
path. Retained validation passed.

## Interpretation

This is a close-group first place. Its slightly leaner dynamic state may help, but the
retained data do not distinguish it strongly from the runner-up's otherwise identical
parallel design.

## Non-decisions

- No generated source or benchmark result is changed.
- No retained sample or score is altered.
