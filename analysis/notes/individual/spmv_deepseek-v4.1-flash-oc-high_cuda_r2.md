# `spmv_deepseek-v4.1-flash-oc-high_cuda_r2`

## Scope

CUDA SpMV at 10,000 rows, density 1/40 (250 nonzeros per row on average), and
50,000 repetitions. The median is 1,595 ms.

## Finding

DeepSeek uses the same decisive organization as the
[previous Luna winner](spmv_gpt-5.6-luna-xhigh_cuda_r1.md): one warp per CSR row,
shuffle reduction, and all repetitions inside one kernel launch. This avoids
50,000 separate launches while retaining the repeated sparse products.

The implementation selects a subgroup width from the average row length. At this
size it selects 32 lanes, so the smaller-subgroup alternatives do not contribute
to the measured result. Its direct row-bound loads differ from Luna's lane-zero
load and broadcast, but the computation has the same structure.

## Close-group comparison

The 1,595 ms median is only 0.39% below Luna's 1,601.226 ms. DeepSeek's samples
span 1,583–1,607 ms; Luna's span 1,594.536–1,653.179 ms. Their overlap supports
treating them as a practical tie, not attributing the ordering to the small
implementation differences. The other fused Luna implementation remains close
at 1,666.574 ms.

## Correctness and timing

Scientific validation passed. The kernel retains the full repetition loop over
the unchanged matrix and input vector. The host timer includes device
synchronization after the kernel; allocation, transfers, and a one-iteration
warmup are outside it. No timing correction was needed.

## Interpretation

DeepSeek reaches the established fast implementation group. This result does not
establish a new performance class or a meaningful advantage over Luna.
