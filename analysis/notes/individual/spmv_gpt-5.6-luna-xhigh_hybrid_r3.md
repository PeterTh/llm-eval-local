# `spmv_gpt-5.6-luna-xhigh_hybrid_r3`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place hybrid result in the `spmv` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used an 18,000-row
matrix with 40 nonzeros per row and 50,000 repetitions on four ranks and four GPUs.
Its times are 1793.625, 1793.366, 1793.484, 1793.547, and 1793.696 ms, with a
1793.547 ms median. The runner-up median is 1797.715 ms.

## Finding

The root rank constructs the CSR matrix, contiguous row slices are distributed, and
the immutable input vector is replicated. Each GPU assigns one warp to each local
row. During the timed interval the host enqueues all 50,000 local SpMV kernels onto a
nonblocking stream and synchronizes once at the end. No MPI communication is needed
inside the repetition loop because neither matrix ownership nor the input vector
changes.

This organization combines balanced distributed row ownership with a conventional,
efficient warp-per-row kernel and minimal host-side synchronization.

## Close-group comparison

The 1797.715 ms runner-up has essentially the same program shape: the same root
construction, row distribution, replicated vector, warp-per-row GPU kernel, 50,000
asynchronously enqueued launches, and final synchronization. Its median is only 0.23%
higher, outside any credible claim of a distinct optimization.

The third result, at 1814.484 ms, keeps the same distributed layout and numerical
kernel but captures the 50,000 launches in a CUDA graph and executes that graph in
the timed interval. It is only 1.2% behind the winner. Thus the whole leading group
implements the same distributed solution; ordinary stream launches and graph replay
reach very similar performance for this fixed workload.

## Correctness and timing validity

Every local row is evaluated in every repetition. The immutable vector makes the
absence of per-iteration communication correct. Device synchronization completes all
queued kernels before time is reduced using maximum semantics across ranks; gathering
the final distributed output occurs outside the repeated computation. Retained
validation passed.

## Interpretation

This is a statistical first place within a very tight, homogeneous group. It should
not be read as evidence that ordinary stream enqueueing is superior to CUDA graphs,
or that the winner discovered a different hybrid decomposition.

## Non-decisions

- No generated source or benchmark result is changed.
- No retained measurement or rank is altered.
