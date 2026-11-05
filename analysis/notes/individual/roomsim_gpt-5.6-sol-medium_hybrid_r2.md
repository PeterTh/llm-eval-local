# `roomsim_gpt-5.6-sol-medium_hybrid_r2`

Date: 2026-11-05

## Scope

The lowest retained Roomsim hybrid median among implementations passing the
complete-array check is 667 ms: 5,120 triangles and 2,000 time steps on four MPI
ranks and four GPUs.

## Finding

Ranks own contiguous receiver rows. Each GPU computes its local form-factor and
delay tables, then updates its receivers while retaining the full radiosity
history. Every time step stages the local result through host memory for
`MPI_Allgatherv`, then copies the gathered row back to the device.

Form-factor computation retains octree visibility tests, with one CUDA thread
per triangle pair looping over 16 rays. Propagation uses a block-level reduction
per receiver. Distance correlation instead gives each receiver one thread that
searches the complete lag range serially.

## Close-group comparison

The leading valid implementations share this distributed GPU design, but their
phase costs differ. Retained medians, in milliseconds:

| Phase | Sol 5.6 Medium r2 | Opus 5.5 Medium r1 | Opus 5 Medium r3 |
| --- | ---: | ---: | ---: |
| Precomp. | 240 | 170 | 195 |
| Prop. | 351 | 374 | 509 |
| Corr. | 76 | 143 | 3 |
| Total | 667 | 687 | 707 |

Sol's lower correlation and propagation times offset its slower precomputation
against Opus 5.5. Opus 5 parallelizes receiver/lag pairs before a separate argmax,
making correlation much faster, but its slower propagation dominates the total.
The 2.9% lead over Opus 5.5 is small: their five-run ranges overlap at 661–674 and
662–702 ms respectively.

## Correctness and timing

All 320 observed distances pass the complete-array check, with maximum difference
2.5 against tolerance 5. Counter-based per-pair sampling replaces the reference's
MT19937 stream, so this is tolerance-based agreement rather than identical
sampling. Phase timers include completed GPU work and MPI barriers, with maximum
time reduced across ranks.

## Interpretation

The small overall lead combines different phase trade-offs; it does not establish
a generally superior hybrid strategy.
