# Nondeterministic Cahn-Hilliard validation

Record `cahn-hilliard_gpt-5.6-terra-xhigh_hybrid_r1` used identical staged source (`5881747d2c910115d1387f9ed7799afe314d784e073b15334f14a0e41664e1d1`) and equivalent
validation commands in the canonical and interrupted replacement runs. The
canonical execution conserved the reference sum and passed comparison; the
replacement execution produced a concentration sum differing by about 0.0288 and
failed comparison.

Inspection found a generated-program race: the CUDA interior update includes
planes adjacent to each MPI rank boundary and reads boundary chemical potentials
produced concurrently on another stream without a synchronization dependency.
This is a program-specific nondeterministic outcome, not a systemic launcher or
validation defect. It therefore did not justify replacing unrelated results.

- canonical manifest: `3634bc842a57e1681ead78d74a90b26135b6efee698e6276521328a98dfd9496`
- replacement manifest: `1aed7f17cb1cf07e71bbb503b418c975fc4412343d001b61674e595d7bead79e`
- retained evidence: source-staging metadata, validation metadata/result, command,
  stdout, stderr, exit code, and wall time from both executions
