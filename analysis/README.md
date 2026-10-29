# Analysis

Release analysis reads versioned campaign records under `data/` and `batches/`,
joined and scored under `release/`. Provisional individual reviews may additionally
use completed native measurements, explicitly pinned in a review snapshot below.
Reusable source belongs in
`src/`, optional output-stripped notebooks in `notebooks/`, final machine-readable
tables in `tables/`, and final figures in `figures/`.

Every completed analysis should document the Git data release/tag it consumed and
provide one command that rebuilds its tables and figures.

The current score/cost and tier outputs consume `release/scored_results.csv`.
`release/scoring_metadata.yaml` pins that file and all campaign inputs by SHA-256;
`release/catalog.json` identifies twelve campaigns, scoped evidence overlays and generated-source commits.
Historical outputs are preserved by Git history and the `local-eval-2026-08-25` tag.

## Tiered LLM comparison

`src/success_rate_tiers.py` reconstructs the tiered success-rate comparison from the
Euro-Par 2026 paper for the expanded local dataset. It preserves the paper's score
tiers:

- Invalid: scores 0-4
- No Speedup: score 5
- OK: scores 6-7
- Good-Top: scores 8-10

Models are sorted by mean overall score from weakest to best. The horizontal layout is
intentional: it keeps all 37 profile names and tier percentages legible at the paper's
full text width. The script requires a balanced number of observations per model and
writes both the vector figure and the exact aggregate table behind it.

Install the locked direct dependencies and rebuild with:

```bash
python -m pip install -r analysis/requirements.txt
python analysis/src/success_rate_tiers.py
```

Canonical outputs:

- `figures/8_success_rate_tiers.pdf`
- `tables/8_success_rate_tiers.csv`

## GPT-5.6 score/cost comparison

`src/gpt56_score_vs_cost.py` compares the nine evaluated GPT-5.6 variant/effort
combinations using the compact scatter-plot style of the paper's score-versus-token
and score-versus-time figures. Marker shape and color identify the model variant;
lines connect low, medium, and xhigh reasoning effort for the same variant. The cost
axis is logarithmic because the current Luna and Sol prices differ by more than an
order of magnitude.

GPT-5.6 token counts come from retained Codex session records, with session and
transcript hashes binding each observation to its program-generation run.
Costs price uncached input, cached input, and output separately.
Cached input is a subset of input and reasoning is a subset of output; neither is
added twice. This remains an API-rate comparison, not a ChatGPT subscription bill.
The backing CSV records counts, frozen prices, pricing date, and source URLs.

The evidence lives in `metadata/codex-usage/<source-batch>.jsonl`. All 1,980
GPT-5.6, 660 GPT-6 and 660 GPT-6.1 records matched a unique session, completed task,
transcript hash, and consistent final cumulative counters. The release uses these
counters for all three families.
The compact usage records total 2,855,653 bytes; complete session logs are not duplicated.
Terra 6.1 additionally retains a compact request-level proof that all 2,583 requests
fall below its long-context pricing threshold.

Recover a completed batch from the original locally retained sessions with:

```bash
ruby method/codex-usage/recover_codex_usage.rb \
  --batch=/path/to/generated/20260929-135931 --expected=660 \
  --sessions=/home/llmtest/.codex/sessions --session-user=llmtest \
  --output=/path/to/new/20260929-135931.jsonl
ruby tools/current_release.rb
```

The recovery tool only reads sessions and exports whitelisted counters/provenance;
it makes no model calls and refuses to overwrite different evidence. Omit
`--session-user` when the invoking account can read the session files directly.
Future evaluation aggregation accepts this file with `--codex-usage=PATH`.
Codex's [machine-readable usage documentation](https://learn.chatgpt.com/docs/non-interactive-mode#make-output-machine-readable)
also describes the input, cached-input, output, and reasoning categories.

Prices versioned for 2026-08-22 are $4/$20 per million input/output tokens for Sol,
$2/$12 for Terra, and $0.20/$1.20 for Luna:

- <https://developers.openai.com/api/docs/models/gpt-5.6-sol>
- <https://developers.openai.com/api/docs/models/gpt-5.6-terra>
- <https://developers.openai.com/api/docs/models/gpt-5.6-luna>

Rebuild with:

```bash
python analysis/src/gpt56_score_vs_cost.py
```

Roboto Condensed must be installed. The script fails instead of silently substituting
a different font so the paper styling remains reproducible.
Alternatively pass `--font /path/to/RobotoCondensed.ttf` to any of the three figure
scripts. The release uses the web lockfile's `@fontsource-variable/roboto-condensed`
Latin normal WOFF2, decompressed with `fonttools ttLib.woff2 decompress INPUT -o OUTPUT`.
Keep temporary fonts, Python caches and build workspaces outside the repository.

Canonical outputs:

- `figures/4c_gpt56_score_vs_cost.pdf`
- `tables/4c_gpt56_score_vs_cost.csv`

## All-model score/cost comparison

`src/all_models_score_vs_cost.py` extends the score-versus-cost view to every
evaluated model except the Qwen Pi-T experiment. To keep the figure readable, only
the xhigh result is retained for each GPT-5.6 variant. OpenRouter pricing profiles
use dated snapshots of public, non-batch endpoints. The selected endpoint is
the one that minimizes estimated cost for that model's observed token mix; Flex is
eligible, and cached tokens use the normal input rate if an endpoint lists no cache
discount. Gemini 3 Pro Preview is retired and absent from the live catalog, so its
last OpenRouter input/output price is paired with a current public cached-input
price. The evaluated Qwen 3.6 27B U-DQ4 model is matched to the cheapest endpoint for
the underlying Qwen 3.6 27B model, currently an FP8 endpoint.

Cost is computed per run from uncached input, cached input, and output tokens before
averaging. The backing CSV records the method,
all rates, selected providers and routing tags, model matches, source URLs, and the
per-model pricing date: 2026-08-22 for existing profiles, 2026-09-29 for the three
Claude 5 additions, 2026-10-02 for GPT-6, 2026-10-06 for Opus 5.5, 2026-10-11
for Sol 6.1, 2026-10-14 for Haiku 5.5, 2026-10-15 for Sonnet 5.5 and 2026-10-18
for Sol 6.1 in OpenCode, 2026-10-19 for Luna 6 in OpenCode, 2026-10-24
for DeepSeek V4.1 Flash in OpenCode, and 2026-10-28 for Haiku 5.5 in OpenCode
and Terra 6.1 in Codex.
The GPT-6 and GPT-6.1 profiles use officially
published non-batch OpenAI Flex prices. Rates are frozen per model.
See [Claude pricing](notes/2026-09-29-claude5-pricing.md) and
[GPT-6 pricing and limitations](notes/2026-10-02-gpt6-pricing.md),
[Opus 5.5 pricing](notes/2026-10-06-opus55-pricing.md) and
[Sol 6.1 pricing](notes/2026-10-11-sol61-pricing.md),
[Haiku 5.5 request-context pricing](notes/2026-10-14-haiku55-pricing.md), and
[Sonnet 5.5 pricing](notes/2026-10-15-sonnet55-pricing.md), and OpenCode native
accounting and pricing for [Sol 6.1](notes/2026-10-18-sol61-opencode-pricing.md)
and [Luna 6](notes/2026-10-19-luna6-opencode-pricing.md), plus
[DeepSeek V4.1 Flash pricing and partial accounting](notes/2026-10-23-deepseek41-opencode-pricing.md)
and [Haiku 5.5 OpenCode pricing](notes/2026-10-28-haiku55-opencode-pricing.md),
and [Terra 6.1 pricing](notes/2026-10-29-terra61-pricing.md).
Haiku 5.5 uses retained per-run token totals grouped by each request's context tier;
OpenCode provides per-request output directly, while Claude Code mixed-tier
output splits are derived from native output and list-price totals.
Cache creation uses ordinary input rates for all Claude profiles. Other profiles
do not model long-context surcharges. Terra 6.1 in Codex and the Sol and Luna OpenCode campaigns
verify that all native requests are below their long-context thresholds;
DeepSeek's selected endpoint has flat context pricing. Three model-terminated
DeepSeek sessions have only partial usage counters and are excluded from
full-task cost statistics, while retaining their scientific outcomes and scores.
Storage, tools, future provider routing changes, and batch discounts are not modeled.

Rebuild with:

```bash
python analysis/src/all_models_score_vs_cost.py
```

Canonical outputs:

- `figures/4d_all_models_score_vs_cost.pdf`
- `tables/4d_all_models_score_vs_cost.csv`

Focused follow-up notes:

- `notes/2026-08-22-sol-xhigh-mpi-simd-classification.md` documents why the larger
  invalid segment for GPT-5.6 Sol xhigh is primarily an MPI/OpenMP-SIMD classification
  boundary rather than a general increase in later-stage validation failures.

## Native and OpenCode harness comparisons

The [Sol 6.1](notes/2026-10-18-sol61-harness-comparison.md) and
[Luna 6 comparisons](notes/2026-10-19-luna6-harness-comparison.md) compare Codex and
OpenCode; the [Haiku 5.5 comparison](notes/2026-10-28-haiku55-harness-comparison.md)
compares Claude Code and OpenCode. All use 220 programs per profile for
validation, score, generation time and cost. Runtime
comparisons use each cell's median successful program and report both
success-conditional and all-programs-successful cell selections. They are
descriptive, not estimates of a pure causal harness effect.

```bash
python analysis/src/harness_comparison.py --comparison sol61
python analysis/src/harness_comparison.py --comparison luna6
python analysis/src/harness_comparison.py --comparison haiku55
```

Each pair writes `tables/<pair>_harness_summary.csv`,
`tables/<pair>_harness_cells.csv` and `tables/<pair>_harness_context.json`; the last
pins the exact scored input and aggregation rules. The original
`src/sol61_harness_comparison.py` command remains supported. Exact OpenCode
accounting, session hashes, shared configuration and pricing checks are retained
under each batch's `generation/`, without duplicating raw transcripts.

## Timing-correction impact

This historical analysis remains scoped to the original 4,620-program campaign and
its 587 corrections; it consumes `data/`, not the jointly rescored `release/` view.
The additional 174 corrections were made before benchmarking, so no comparable
uncorrected performance measurements exist for those runs. The current combined
dataset carries the timing-fix flag for 1,196 distinct corrected programs, including
two failed revalidations. The 81 newer corrections include 12 previously retimed
historical QT programs. Their 32 scoped historical reruns are retained separately
under `corrections/20261001-gpt6-qt/`, not folded into this older 587-case analysis.
The 83 Opus 5.5, 11 native Sol 6.1, 33 Haiku 5.5, 71 Sonnet 5.5, 14 Sol 6.1
OpenCode, 39 Luna 6 OpenCode, 56 current DeepSeek OpenCode, 36 Haiku 5.5 OpenCode
and 26 Terra 6.1 Codex corrections likewise
precede those programs' benchmarks.

The retained historical analysis joins the original static-audit score, corrected scoped-rerun
measurements, final scores, issue categories, and original/corrected source links:

```bash
ruby analysis/src/timing_correction_analysis.rb
```

It produces a per-program detail table, grouped benchmark/backend/model summaries, an
issue-category table, all audited MPI/hybrid score changes caused by re-thresholding,
and `analysis/timing-correction-report.md`. Measurement-quality columns retain
repetition spread and wall-to-reported-time ratios so short/setup-dominated cases stay
visible. The generated report is descriptive: an invalid rank-local time is not treated
as a calibratable estimate of the corrected global makespan.

Do not commit notebook cell output, caches, serialized interpreter workspaces, or
intermediate datasets. Prefer CSV for tables and PDF for vector figures; retain one
canonical format unless the publication toolchain requires another.

## Individual implementation reviews

Published run reviews live in `notes/individual/` and are embedded by the website.
All 44 current cell winners have reviews; 94 notes are retained, including superseded winners.
Terra 6.1 Medium in Codex introduces no new cell winners. Its
[comparison snapshot](notes/2026-10-29-terra61-codex-winner-context.json) verifies
that all 7,920 prior observations are unchanged against the preceding release;
153 prior scores change solely through joint thresholds.
Check it with `ruby analysis/src/check_terra61_reviews.rb`.

DeepSeek V4.1 Flash High in OpenCode introduces one new winner:
[CUDA SpMV](notes/individual/spmv_deepseek-v4.1-flash-oc-high_cuda_r2.md), a practical
tie with Luna's existing fused-kernel implementation. Its
[comparison snapshot](notes/2026-10-23-deepseek41-opencode-winner-context.json)
pins the measured vectors, peer sources and unchanged 7,480 prior observations.
Check it with `ruby analysis/src/check_deepseek41_reviews.rb`.

Luna 6 Medium in OpenCode introduces no new cell winners. Its
[comparison snapshot](notes/2026-10-19-luna6-opencode-winner-context.json) verifies
that all 7,260 prior observations are unchanged against the preceding release;
222 prior scores change solely through joint thresholds.
The [release check record](notes/2026-10-19-luna6-opencode-release-checks.json)
retains accounting, preservation, test, retention and visual-inspection results.

Sol 6.1 Medium in OpenCode introduces no new cell winners. Its
[comparison snapshot](notes/2026-10-18-sol61-opencode-winner-context.json) verifies
that all 7,040 prior observations are unchanged against the preceding release;
57 prior scores change solely through joint thresholds.
The [release check record](notes/2026-10-18-sol61-opencode-release-checks.json)
retains accounting, preservation, test, retention and visual-inspection results.

Sonnet 5.5 introduces no new cell winners. Its
[comparison snapshot](notes/2026-10-16-sonnet55-winner-context.json) verifies that
all 6,820 prior observations are unchanged against the preceding release;
114 prior scores change solely through joint thresholds.
The [release check record](notes/2026-10-16-sonnet55-release-checks.json) retains
accounting, preservation, test and visual-inspection results.

Haiku 5.5 introduces no new cell winners. Its
[comparison snapshot](notes/2026-10-14-haiku55-winner-context.json) verifies that
all 6,600 prior observations are unchanged against the preceding release;
84 prior scores change solely through joint thresholds.
The [release check record](notes/2026-10-14-haiku55-release-checks.json) retains
accounting, preservation, test and visual-inspection results.

The Sol 6.1 release added seven winner reviews.
Their [comparison snapshot](notes/2026-10-11-sol61-winner-context.json) pins
the preceding release at `d2675741cb5ac74cea6fd94fb38f46aef11cb4b4`, all new benchmark
record digests, source revisions and close-group samples. All 6,160 prior
observations are unchanged; 97 scores change only through joint thresholds.
Check these notes and the bounded diagnostic with
`ruby analysis/src/check_sol61_reviews.rb`. On the source host,
`ruby analysis/src/sol61_review_context.rb /path/to/llm-eval-generated --check`
also reconstructs the source pins and checks the complete prior observations.
The [release check record](notes/2026-10-11-sol61-release-checks.json) records
the preservation checks, source dependencies, test counts and visual inspection.

### Limited Sol 6.1 SpMV diagnostic

The separated SpMV/MPI winner received one bounded test of its four-row
interleaving. Its original and single-change scalar variant each ran once for
correctness at the full 10,000-row size, once for warmup and three times for
measurement: ten executions total, using the established 128-rank profile and
50,000-iteration measurement workload. Measurement order alternates. Their
medians are 1,195.279 and 1,417.597 ms, supporting interleaving as the main
explanation for the lead. Both correctness checks and the native numerical
comparison passed. Canonical measurements, scores and generated sources are unchanged.

The [compact evidence](notes/2026-10-11-sol61-spmv-diagnostic.json) retains
all outputs, source and executable hashes, commands, build logs and sample
vectors. Only a one-line patch is stored beside it, not copied program sources
or binaries. To reproduce, extract the context's pinned source into `baseline/`
and `scalar/` under a local `/tmp` workspace, apply
`notes/2026-10-11-sol61-spmv-diagnostic/scalar-loop.patch` with `patch -p1`
in `scalar/`, then invoke `analysis/src/sol61_spmv_diagnostic.rb` with
`--pipeline`, `--workspace` and a new persistent `--output` path. The pipeline
must reconstruct the pinned campaign method. This diagnostic is not part of
ordinary release rebuilding or a reason to rerun the published benchmarks.

### Earlier winner reviews

The Opus 5.5 release added 13 winner reviews, bringing the retained total then to 86.
Their [comparison snapshot](notes/2026-10-06-opus55-winner-context.json) pins
the preceding release at `c31465ba90faecbbc567de7e51de694c512e379f`, all new benchmark
record digests, source revisions and close-group samples. These reviews use source
inspection and retained phase metrics; no new program executions were performed.
Check their structure, links, source-pin consistency and unchanged measurements with
`ruby analysis/src/check_opus55_reviews.rb`. On the source host,
`ruby analysis/src/opus55_review_context.rb /path/to/llm-eval-generated --check`
also reconstructs the complete context from the pinned Git sources and baseline.
The compact [release check record](notes/2026-10-06-opus55-release-checks.json)
records preservation checks, test counts and desktop/mobile visual inspection.

The five new GPT-6 winner reviews are integrated in `notes/individual/`; the website
continues to reject reviews for unreleased IDs. The 2026-10-02 work adds five notes
and rewrites all 24 Claude-5 notes, giving 73 retained reviews in total.
One older SpMV scope sentence is also corrected: `-s 40` means one nonzero per
40 matrix entries, not 40 nonzeros per row.

The [review snapshot](notes/2026-10-02-winner-review-context.json) pins artifact
commit `7aa7ea28c484b508b6ba12ce991773fc1050b41c`, benchmark input digests and
generated-source revisions. This is the rebased equivalent of the reviewed
`c6984fc`; the snapshot retains the original SHA, and all scientific artifact files
are byte-identical between those commits. It combines the published campaigns with the completed
`20261001-gpt6-validation` measurements and the limited historical QT rerun
`20261001-gpt6-qt-corrected`. Native rerun records replace the same IDs rather than
being counted twice. This frozen review comparison predates integration; its
measurements are unchanged in the integrated release. The source pins identify
comparison inputs, not 99 independent full
correctness audits.

Reviews use a short Scope, then Finding, Close-group comparison, Correctness and
timing, and Interpretation. Depth follows separation from the nearest competitive
group, sample spread and the implementation distinction; 15% is not a threshold.
Near ties link earlier group reviews instead of repeating them. Medians and ranges
describe five retained repetitions, not confidence intervals or paired trials.
Source-visible explanations are identified as such; an optimization shared by the
nearest peer cannot alone explain their difference. OpenMP campaign memory is
NUMA-interleaved, so parallel initialization alone does not demonstrate local
first-touch placement. Common provenance stays here and in machine-readable
records, rather than being repeated in every note.

Check all 29 notes, links, comparison medians, diagnostic evidence and unchanged
versioned benchmark inputs with:

```bash
ruby analysis/src/check_winner_reviews.rb
```

On the measurement host, additionally verify the native input digests with
`--local-evaluation=/home/petert/llm_para_local_evaluation`. The context snapshot
retains the comparison vectors needed to read the notes without those workspaces.
Retained Claude QT correctness probes are in
`notes/2026-09-29-qt-winner-correctness.json`; they are not new GPT-6 probes.

### Limited Black–Scholes diagnostic

The only new program executions for these reviews were a bounded diagnostic of
`black-scholes_gpt-6-sol-medium_cuda_r3`: one baseline and two single-change
variants, each with one correctness run, one warmup and three measured runs
(15 executions total). The measured order rotates between variants. The
[compact record](notes/2026-10-02-black-scholes-diagnostic.json) retains all outputs,
sample vectors, source hashes, build/run settings and numerical-comparison results.
Two small patches are retained beside it; source trees and binaries are not.

The full-formula variant disables seven-contract price reuse. The download variant
keeps that arithmetic but includes the device-to-host result copy in the interval.
The baseline, full-formula and download medians are 1.225, 34.317 and 18.667 ms; the download
samples are variable (18.375–26.525 ms). The correctness comparison uses the
unchanged, previously validated winner at 10,000 options and the existing validator:
it is not a new full-size sequential-reference test. The full-formula outputs pass
the numerical tolerance but are not bit-identical.

For reproduction, extract the pinned generated run into three separate local
workspaces using `git archive`, apply the corresponding patch with `patch -p1` in
each variant root, and use the recorded CMake configure/build commands. The source's
target sets the effective CUDA architecture to `native`; the diagnostic ran on an
RTX 3090. Use the recorded argument sets and rotation order with the campaign's
CUDA resource binding (`CUDA_VISIBLE_DEVICES=0`, `OMP_NUM_THREADS=1`, CPU 0–63,
NUMA node 0). The experiment pipeline's host-performance lock and process/resource
containment were used; its commit is pinned in the record. Do not run this alongside
benchmarking or model tuning, and keep all temporary builds off NFS. To reproduce
the report's median table without running any programs, use the checker above and
read the diagnostic's `variants` object.

These diagnostic timings never enter benchmarking or scoring. They show why the
outlier needs both an arithmetic-specialization explanation and an explicit
result-transfer boundary, not a blanket claim about general pricing throughput.
