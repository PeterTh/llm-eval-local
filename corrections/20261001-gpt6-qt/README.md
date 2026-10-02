# Shared GPT-6 / QT timing corrections

One timing-only source commit covers 81 implementations across eight source batches:
49 new GPT-6 programs and 32 historical QT programs. All 81 proposals compiled and
received independent acceptance. Corrected numerical validation passed for 79;
the two pre-existing GPT-6 defects remain failures under explicit user decisions.
No algorithm, parser or output repair was made. All 79 passing numerical RESULTS
blocks are byte-identical to earlier validation evidence.

The all-backend QT review covered all 425 validated implementations, including
historical benchmark failures. Luna performed the primary static reviews; Sol-6.1
adjudicated 63 selected cases. Final decisions: 378 valid, 47 needing timing-only
correction, none ambiguous. QT timing includes algorithmic distance/neighborhood
preprocessing. Combined with the 34 non-QT GPT-6 corrections, this produces the
81-source registry. No benchmark or correctness executions occurred during static review.

Only the 32 affected historical QT programs were rebenchmarked (14 successes,
18 timeouts), using unchanged sizes, iterations and resources. Their success/failure
statuses did not change. `release-guard.json` binds all 4,435 unrelated historical
records and the archived input files; `rerun-comparison.jsonl` gives the 32 before/
after observations. Earlier records stay in their original campaign directories.

`final/corrections.jsonl` is the unmodified accepted registry. Its “original” source
is the baseline of this correction step, not necessarily the first generated source.
`source-history.jsonl` resolves that distinction: 12 previously corrected programs
have initial, intermediate and final links. The website exposes all three versions.
`final/validation-failures.json` binds both failure decisions to source revisions,
validation outputs and retained independent diagnoses. Those programs cannot regain
benchmark eligibility merely because their first validation passed.

The final completion report/checker, scope, guards and driver snapshots are in
`completion/`; native benchmark provenance and exact failed-execution logs are in
`benchmark/`. Corrections, prompts, proposal revisions, compilation outcomes and
independent review results are retained without binaries or complete agent streams.

Re-export from the retained native evidence (writes only the requested artifact root):

```sh
ruby tools/export_gpt6_campaign.rb --root=/path/to/pre-integration-artifact \
  --experiment=/path/to/llm-eval-experiment --evidence-home=/home/petert
ruby tools/prepare_gpt6_overlay.rb
ruby tools/current_release.rb --require-reviews
```

Use a pre-integration checkout for the one-time overlay preparation. Release rebuilds
and verification thereafter require only this repository and Ruby's standard library.
