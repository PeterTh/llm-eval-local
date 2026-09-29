# `cahn-hilliard_claude-opus-5-cc-medium_mpi_r4`

Date: 2026-09-29

Status: static winner review against retained validation and measurements; no additional source or measurement change proposed

## Scope and evidence

New nominal winner in `cahn-hilliard/mpi` after adding batch `20260901-162328` to the combined release. The inherited arguments are `-x 256 -i 2000`; calibration and resources were not changed for this batch.

The five retained times are 1388.0, 1383.0, 1391.0, 1377.0, 1384.0 ms, median **1384.0 ms**. The [previous winner](https://github.com/PeterTh/llm-eval-local/blob/7c91b05a5ba6b7c5991d7177211f173cdd4b4fdb/analysis/notes/individual/cahn-hilliard_gpt-5.6-luna-xhigh_mpi_r2.md), `cahn-hilliard_gpt-5.6-luna-xhigh_mpi_r2`, had times 1407.0, 1414.0, 1409.0, 1418.0, 1404.0 ms and median 1409.0 ms. The old/new median ratio is 1.0181x. This compares independent campaigns, not paired measurements or a confidence interval.

Reviewed [source](https://github.com/PeterTh/llm-eval-generated/blob/db27e2872a28b900024d318f6a3004a3a7fddfa7/20260901-162328/cahn-hilliard_claude-opus-5-cc-medium_mpi_r4/cahn-hilliard/cahn_hilliard.cpp); file SHA-256 `27fe69d0fc80cff4f8bf672aea74db684e2e4b400843b70b10e90804a299edcd`. Timing-fixed flag: **false**. This program did not require a timing correction in the retained campaign.

## Implementation and timing

A two-dimensional Y/Z pencil decomposition keeps X contiguous for vectorization. Nonblocking halo exchange overlaps the strictly interior part of each chemical-potential and concentration sweep; boundary bands run after `MPI_Waitall`. Physical-domain halos copy adjacent interior values, preserving the reference's clamped boundary condition. Both sweeps and all requested time steps are present.

A barrier precedes `MPI_Wtime`; the final elapsed time is reduced with `MPI_MAX` over the Cartesian communicator. The output gather is separate from the timed evolution.

The median lead is only about 1.8%. The five samples form a slightly faster group, but they come from a later campaign and do not establish a durable advantage over the former winner. Treat first place as a nominal ordering within a close performance group, not as an algorithmic breakthrough.

## Limits and release decision

The retained program passed all five validation stages. That is empirical evidence for the established test input, not a formal proof for every size or machine. The code inspection above checks the measured execution path and timing boundaries; optimization comments alone are not treated as measured causal evidence.

This note leaves generated source, validation outcomes, and all retained timing vectors unchanged. Joint release scoring is recomputed mechanically from the combined distribution by the existing threshold method; the review itself does not award extra points or replace measurements.
