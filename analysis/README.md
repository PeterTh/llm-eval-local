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
`release/catalog.json` identifies four campaigns, the scoped QT overlay and generated-source commits.
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
intentional: it keeps all 28 model names and tier percentages legible at the paper's
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
GPT-5.6 and 660 GPT-6 records matched a unique session, completed task, transcript
hash, and consistent final cumulative counters. The release uses these counters
for both model families.
The compact evidence totals 2,283,539 bytes; complete session logs are not duplicated.

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
Claude 5 additions, 2026-10-02 for GPT-6, and 2026-10-06 for Opus 5.5. The GPT-6 profiles use officially
published non-batch OpenAI Flex prices. Rates are frozen per model.
See [Claude pricing](notes/2026-09-29-claude5-pricing.md) and
[GPT-6 pricing and limitations](notes/2026-10-02-gpt6-pricing.md), and
[Opus 5.5 pricing](notes/2026-10-06-opus55-pricing.md).
Long-context surcharges, storage, tools, future provider
routing changes, and batch discounts are not modeled.

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

## Timing-correction impact

This historical analysis remains scoped to the original 4,620-program campaign and
its 587 corrections; it consumes `data/`, not the jointly rescored `release/` view.
The additional 174 corrections were made before benchmarking, so no comparable
uncorrected performance measurements exist for those runs. The current combined
dataset carries the timing-fix flag for 913 distinct corrected programs, including
two failed revalidations. The 81 newer corrections include 12 previously retimed
historical QT programs. Their 32 scoped historical reruns are retained separately
under `corrections/20261001-gpt6-qt/`, not folded into this older 587-case analysis.
The 83 Opus 5.5 corrections likewise precede that campaign's first benchmarks.

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
The Opus 5.5 release adds 13 winner reviews, bringing the retained total to 86.
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
