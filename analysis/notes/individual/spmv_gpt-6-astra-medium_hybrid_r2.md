# `spmv_gpt-6-astra-medium_hybrid_r2`

Date: 2026-10-02

## Scope

Hybrid SpMV, `-n 18000 -s 40 -i 50000`. Here `-s 40` means one nonzero per
40 matrix entries: about 8.1 million nonzeros, or 450 per row. The median is
1,718.238 ms, versus 1,723.423 ms for Astra 6 r5 and 1,793.547 ms for the previous
Luna 5.6 xhigh winner.

## Finding

Contiguous CSR row partitions balance nonzero work plus a per-row cost. On this
input, a full warp reduces each row. A CUDA graph batches 32 SpMV launches, reducing
host submission overhead while still computing every requested iteration.

## Close-group comparison

Astra r5 uses closely related partitioning and kernels but batches 64 launches.
The 0.3% median difference is small; this does not isolate graph batch size as its
cause. Against the older winner the lead is 4.2%, within the same distributed CSR
design described in the
[existing group review](../individual/spmv_gpt-5.6-luna-xhigh_hybrid_r3.md).

## Correctness and timing

Retained validation and timing review passed. Uploads, warmup and graph capture
precede timing. The timed loop executes exactly 50,000 matrix-vector products,
including the final partial batch, then synchronizes before the maximum-rank
reduction. Reusing an unchanged input vector does not remove those products.

## Interpretation

A modest improvement within a common GPU-resident implementation family, with no
evidence that the narrow r2/r5 ordering represents a distinct algorithmic advance.
