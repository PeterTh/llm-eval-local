# GPT-6 medium campaign: 20260929-135931

Sol, Luna and Astra each generated 220 programs (11 benchmarks × four backends ×
five independent repetitions). Generation used Codex CLI 0.159.0 and medium
reasoning effort. `generation/campaign.json` and the exact launch snapshots retain
the model IDs, disabled tools, hashes and source-worktree provenance.

Original generated source: `32f1becd283322d1edff43dd47a3b3bc8e2cdad6`.
Timing-corrected source: `3a47d7cba6624f4bdfe004fba3383b5e3c62e93f`.
Source and transcripts remain in `llm-eval-generated`; they are not duplicated here.

Initial validation observed 611 passes and 49 failures. The shared timing correction
campaign revalidated 49 GPT-6 programs; 47 passed, while a pre-existing N-body race
and RoomSim MPI output-contract defect failed. The user explicitly retained both
failures. Effective eligibility is 609 passes / 51 failures; originals are immutable.
See [the shared correction evidence](../../corrections/20261001-gpt6-qt/README.md).

Benchmarking completed 2026-10-02: 588 successes, 20 warmup timeouts and one warmup
MPI gather crash. Sol and Astra each succeeded on all 219 eligible programs; Luna
succeeded on 150/171. No failures were retried. All 44 inherited argument/iteration/
timeout cells and resource profiles were unchanged: one warmup and five measurements.

`validation/records/<benchmark>/<backend>.jsonl` preserves metadata and exact
execution logs; `benchmark/records/` preserves native measurements and provenance.
Failed benchmark logs are retained; successful benchmark metadata can be reconstructed
exactly using `evidence-index.jsonl`, the manifest and `tools/shared_corrections.rb`.
Pipeline layouts map original experiment paths to repository-relative retained
snapshots; identical older method files are reused by hash.

`aggregate/` was built with the frozen native parser/serializer, corrected validation
observations and exact recovered tokens. Its receipt binds every source input.
This batch is part of the scored `release/` and the website, not provisional data.
