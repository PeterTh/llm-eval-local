# Execution System

This is the system recorded by the immutable manifest and live launcher preflights
for canonical run `20260819-003427`. Raw initialization, validation, and
benchmark preflights are retained under `preflight/`.

## Hardware

- Host identifier: `gpuc3`
- Physical cores available to the pipeline: 128
- NUMA nodes: 0, 1
- GPUs: four NVIDIA GeForce RTX 3090 devices, 24,576 MiB each
- Persistent run storage: local NVMe-backed XFS under `/home`
- Free space recorded at initialization: 2552571232256 bytes
- Cgroup containment enabled: true

## Toolchain

- ruby 3.2.3 (2024-01-18 revision 52bb2ac0a6) [x86_64-linux-gnu]
- cmake version 3.30.2
- C compiler: gcc-13 (Ubuntu 13.2.0-23ubuntu4) 13.2.0
- C++ compiler: g++-13 (Ubuntu 13.2.0-23ubuntu4) 13.2.0
- CUDA compiler: Build cuda_12.6.r12.6/compiler.34841621_0
- MPI: mpirun (Open MPI) 4.1.6

## Resource profiles

| Phase | Backend | Effective resources |
|---|---|---|
| validation | omp | 8 physical cores on NUMA node 0 |
| validation | cuda | GPU 0 and 8 host cores on NUMA node 0 |
| validation | mpi | 4 ranks, 2 per socket, 1 physical core per rank |
| validation | hybrid | 4 ranks, 2 per socket, 8 cores and 1 topology-local GPU per rank |
| benchmark | omp | 128 physical cores across both sockets, interleaved memory |
| benchmark | cuda | GPU 0 and physical cores 0-63 on NUMA node 0 |
| benchmark | mpi | 128 ranks, 64 per socket, 1 physical core per rank |
| benchmark | hybrid | 4 ranks, 2 per socket, 32 cores and 1 topology-local GPU per rank |

## CPU topology (`lscpu`)

```text
Architecture:                         x86_64
CPU op-mode(s):                       32-bit, 64-bit
Address sizes:                        48 bits physical, 48 bits virtual
Byte Order:                           Little Endian
CPU(s):                               256
On-line CPU(s) list:                  0-255
Vendor ID:                            AuthenticAMD
Model name:                           AMD EPYC 7763 64-Core Processor
CPU family:                           25
Model:                                1
Thread(s) per core:                   2
Core(s) per socket:                   64
Socket(s):                            2
Stepping:                             1
Frequency boost:                      enabled
CPU(s) scaling MHz:                   57%
CPU max MHz:                          3530.0000
CPU min MHz:                          400.0000
BogoMIPS:                             4900.02
Flags:                                fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf rapl pni pclmulqdq monitor ssse3 fma cx16 pcid sse4_1 sse4_2 x2apic movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw ibs skinit wdt tce topoext perfctr_core perfctr_nb bpext perfctr_llc mwaitx cpb cat_l3 cdp_l3 hw_pstate ssbd mba ibrs ibpb stibp vmmcall fsgsbase bmi1 avx2 smep bmi2 erms invpcid cqm rdt_a rdseed adx smap clflushopt clwb sha_ni xsaveopt xsavec xgetbv1 xsaves cqm_llc cqm_occup_llc cqm_mbm_total cqm_mbm_local user_shstk clzero irperf xsaveerptr rdpru wbnoinvd amd_ppin brs arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold v_vmsave_vmload vgif v_spec_ctrl umip pku ospke vaes vpclmulqdq rdpid overflow_recov succor smca fsrm debug_swap
Virtualization:                       AMD-V
L1d cache:                            4 MiB (128 instances)
L1i cache:                            4 MiB (128 instances)
L2 cache:                             64 MiB (128 instances)
L3 cache:                             512 MiB (16 instances)
NUMA node(s):                         2
NUMA node0 CPU(s):                    0-63,128-191
NUMA node1 CPU(s):                    64-127,192-255
Vulnerability Gather data sampling:   Not affected
Vulnerability Itlb multihit:          Not affected
Vulnerability L1tf:                   Not affected
Vulnerability Mds:                    Not affected
Vulnerability Meltdown:               Not affected
Vulnerability Mmio stale data:        Not affected
Vulnerability Reg file data sampling: Not affected
Vulnerability Retbleed:               Not affected
Vulnerability Spec rstack overflow:   Mitigation; Safe RET
Vulnerability Spec store bypass:      Mitigation; Speculative Store Bypass disabled via prctl
Vulnerability Spectre v1:             Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2:             Mitigation; Retpolines; IBPB conditional; IBRS_FW; STIBP always-on; RSB filling; PBRSB-eIBRS Not affected; BHI Not affected
Vulnerability Srbds:                  Not affected
Vulnerability Tsx async abort:        Not affected
```

## GPU inventory

```text
0, NVIDIA GeForce RTX 3090, 24576 MiB, 8.6, 560.35.03
1, NVIDIA GeForce RTX 3090, 24576 MiB, 8.6, 560.35.03
2, NVIDIA GeForce RTX 3090, 24576 MiB, 8.6, 560.35.03
3, NVIDIA GeForce RTX 3090, 24576 MiB, 8.6, 560.35.03
```

Generated configure/build/run processes were executed in transient user-systemd
scopes. Builds were limited to 32 GiB/256 tasks, validation to 64 GiB/256 tasks,
and calibration/benchmarking to 256 GiB/512 tasks. Stdout and stderr were drained
with an 8 MiB retained cap; process-tree timeouts and TERM/KILL cleanup remained
active. The operator kept unrelated load off the system during performance runs.
