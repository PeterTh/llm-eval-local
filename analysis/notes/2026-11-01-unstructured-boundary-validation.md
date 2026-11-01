# Unstructured: boundary-sensitive external validation

## Finding

The Unstructured MPI and hybrid validation input could miss incorrect halo
exchange. Its 256×256 grid ran for 20 iterations on four ranks. For a row
partition, each rank owns 64 rows; for a 2×2 partition, each block spans 128×128
elements. Corner forcing propagates through nearest-neighbor updates and need
not reach an internal partition boundary within those 20 iterations. A program
could therefore pass the numerical comparison despite exchanging too little,
misdirected or stale boundary data.

The issue was found while reviewing `unstructured_beam-1.0-oc-medium_mpi_r2`:
its halo transfer counts doubles as though a two-double structure contained
only one. This is an algorithmic error, not a timing-measurement error.

## Check and scope

The additional external-validation case uses `-v -r -n 32 -i 512`, four MPI
ranks and the existing MPI/hybrid resource profiles and 30-second timeout.
The smaller grid and longer evolution exercise communication between partitions.
Both this case and the original case are required for future Unstructured MPI
and hybrid validation. Sequential input programs, generated programs, numerical
comparison code and tolerances are unchanged. Result hashes remain informational.

The retrospective check covered all **277 published successful Unstructured
MPI/hybrid measurements** in release `091a833` and all **10 Beam implementations**
that passed the original validation. It used each observation's exact effective
source revision, including existing timing-only corrections. We reused 252
source-verified build caches and rebuilt the other 35 locally. The pilot's
accepted results were reused, not repeated.

The 287 checks completed in 17 minutes 46 seconds including rebuilds: **279
passed and eight failed**. Every failure exited normally and passed internal
validation, but failed the unchanged numerical external comparator. There were
no timeouts or infrastructure failures. Execution averaged 1.51 seconds for MPI
and 5.50 seconds for hybrid, including launch overhead. No performance benchmarks
were rerun.

## Failed implementations

All IDs below have the prefix `unstructured_`. The
[static findings](../../validation-supplements/20261101-unstructured-boundary/static-findings.json)
retain exact source revisions, paths and line references.

| ID suffix | Static explanation consistent with the numerical failure |
| --- | --- |
| `beam-1.0-oc-medium_mpi_r2` | Transfers only half of each two-double-structure halo row. |
| `deepseek-v4-flash_hybrid_r5` | Installs received halos on opposite sides and copies receive buffers even for absent neighbors. |
| `gpt-5.6-luna-low_mpi_r3` | Reads an interleaved structure row as contiguous energies and transmits only half the row. |
| `gpt-5.6-luna-xhigh_hybrid_r1` | CUDA/MPI staging copies one double per two-double element, leaving half the ghost row stale. |
| `gpt-5.6-terra-medium_hybrid_r5` | Stages the bottom ghost row instead of the last owned row, then sends an unrefreshed host row. |
| `gpt-6-luna-medium_mpi_r5` | Uses the element count as an `MPI_BYTE` count, transferring only 1/16 of the required row bytes. |
| `qwen3.7-plus_hybrid_r4` | Uses stale receive data and refreshes only one of two alternating GPU ghost buffers. |
| `qwen3.7-plus_mpi_r1` | Transfers only half of each two-double-structure halo row. |

The two previously timing-corrected failures already contained their halo bugs
in the original generated source. Those corrections changed timing only.

## Disposition and impact

These eight observations fail **external validation**, with the preceding four
stages still passing: validation score 4. Their algorithms are not repaired and
their generation observations are not replaced. The original validation records
and any historical benchmark measurements remain immutable evidence; the current
release excludes these implementations from eligible performance comparisons and
recomputes derived scores. Timing-correction history remains available where it
exists.

Seven failures were published measurements. Neither overall Unstructured winner
changes: Sol 5.6 xhigh MPI r1 (323.088 ms) and Sol 5.6 low hybrid r5 (2178.706 ms)
both pass. The fastest excluded implementation was Terra 5.6 medium hybrid r5,
previously ninth of 125 hybrid successes. This does not mean per-model summaries
are unchanged. The Beam failure had not been benchmarked; Beam now has 179
eligible implementations and 56 eligible timing corrections, from 180 original
validation passes and 57 timing-invalid audit decisions.

This targeted check closes the identified boundary-propagation blind spot; it
does not prove correctness for every input or decomposition. The
[evidence export](../../validation-supplements/20261101-unstructured-boundary/export.json)
retains all 287 result records, bounded logs, source/build bindings and the
[source-pinned failure disposition](../../validation-supplements/20261101-unstructured-boundary/external-validation-exclusions.json).
Temporary builds and executions used local storage; persistent evidence contains
no binaries or repeated generated-source trees.

Future validation implements the extra case in experiment commit
[`4bc0474`](https://github.com/PeterTh/llm-eval-experiment/commit/4bc0474e97e52215948b734cfd59605581d24550).
