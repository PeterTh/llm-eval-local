# `spmv_gpt-5.6-luna-xhigh_cuda_r1`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place CUDA result in the `spmv` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 10,000-row
matrix with 40 nonzeros per row and 50,000 repetitions. Its times are 1594.536,
1601.226, 1596.834, 1653.179, and 1635.565 ms, giving a 1601.226 ms median. The
runner-up median is 1666.574 ms.

## Finding

The implementation assigns one warp to each CSR row. Lanes traverse the row's
nonzeros in parallel and combine partial sums with warp shuffles. More importantly,
the complete 50,000-repetition loop is inside one kernel launch. This is valid because
every repetition multiplies the same immutable matrix and vector and simply overwrites
the same output value; there is no iteration-to-iteration dependency.

Moving the repetition loop onto the GPU avoids tens of thousands of host launch
operations. That launch fusion is the dominant reason this pair of implementations
is much faster than the rest of the cell.

## Close-group comparison

The 1666.574 ms runner-up uses the same warp-per-row calculation and the same single
kernel containing all repetitions. Minor differences include how row bounds are
loaded and broadcast among lanes, plus an unused scalar alternative in the runner-up.
Those are implementation details, not different solution shapes.

The winner is 3.9% lower by median, but its samples range up to 1653.179 ms and the
runner-up ranges down to 1649.161 ms. They are best treated as a close pair using the
same decisive optimization. The next result, at 2198.3 ms, also uses a warp per row
but launches a kernel for each repetition. Its roughly 37% deficit isolates launch
organization, rather than sparse arithmetic, as the structural distinction.

## Correctness and timing validity

All 50,000 repetitions and every stored matrix nonzero are evaluated. Repeatedly
overwriting the output is semantically identical to separate launches for this
benchmark. The host timer encloses the kernel and synchronizes the device before
returning; allocation and transfers are outside the defined computation interval.
Retained validation passed.

## Interpretation

The fused repetition loop is a genuine cell-level advantage. The exact first-place
ordering of the two fused warp-per-row implementations is much weaker evidence and
should not be attributed to a different algorithm.

## Non-decisions

- No generated source or benchmark result is changed.
- No alternative timing result replaces the retained score.
