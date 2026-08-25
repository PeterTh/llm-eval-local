# `spmv_gpt-5.6-terra-xhigh_mpi_r4`

Date: 2026-08-25

Status: static performance explanation; no validation, measurement, or scoring change

## Scope

This is the first-place MPI result in the `spmv` cell of data release
`local-eval-2026-08-25` at data commit `f83773e`. The benchmark used a 10,000-row
matrix with 40 nonzeros per row and 50,000 repetitions on 128 ranks. Its times are
1378.891, 1381.833, 1386.340, 1377.341, and 1385.503 ms, giving a 1381.833 ms
median. The runner-up median is 1417.276 ms.

## Finding

The matrix is partitioned into contiguous row ranges using cumulative nonzero counts,
which balances sparse arithmetic rather than merely row count. The immutable input
vector is replicated. Each rank then repeats a scalar local CSR traversal 50,000
times without communication inside the timed loop, because each repetition has the
same independent inputs. Restrict-qualified arrays and compact local loops give the
compiler a straightforward optimization target.

## Close-group comparison

The runner-up and the several results clustered between 1417 and 1426 ms use the same
overall method: nonzero-aware contiguous row partitioning, a replicated fixed vector,
and a communication-free repeated local CSR loop. They vary in index widths, boundary
selection details, compiler-visible pointer annotations, and exact placement of
barriers, but do not use a substantively different distributed algorithm.

The winner's median lead over the immediate runner is 2.5%. That is a plausible
implementation-level advantage, but it is not enough to identify one unique cause
from static inspection, and the broader fast group is tightly packed. The correct
interpretation is that the winner is the fastest retained member of the dominant
balanced-CSR design family.

## Correctness and timing validity

All local nonzeros are processed in all 50,000 repetitions. Replication of an
unchanging vector makes communication inside those repetitions unnecessary. Ranks
synchronize around the measurement and report the maximum rank time, so neither
load imbalance nor a fast rank can create an artificially low result. Retained
validation passed.

## Interpretation

This is not an algorithmic outlier. The small lead likely reflects generated-code
and partition-boundary details within a shared solution shape, and should not be
generalized beyond this retained configuration.

## Non-decisions

- No generated source or benchmark result is changed.
- No speculative causal attribution changes the recorded score.
