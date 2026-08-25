# Analysis

Analysis reads only the versioned files under `data/`. Reusable source belongs in
`src/`, optional output-stripped notebooks in `notebooks/`, final machine-readable
tables in `tables/`, and final figures in `figures/`.

Every completed analysis should document the Git data release/tag it consumed and
provide one command that rebuilds its tables and figures.

The checked-in outputs consume the timing-audited data release
`local-eval-2026-08-25` at data commit `f83773e` and
`data/scoring/scored_results.csv` (SHA-256
`7e6012c97b84a3632797cad103093929851d1ff07349205dd7383097927207c9`).

## Tiered LLM comparison

`src/success_rate_tiers.py` reconstructs the tiered success-rate comparison from the
Euro-Par 2026 paper for the expanded local dataset. It preserves the paper's score
tiers:

- Invalid: scores 0-4
- No Speedup: score 5
- OK: scores 6-7
- Good-Top: scores 8-10

Models are sorted by mean overall score from weakest to best. The horizontal layout is
intentional: it keeps all 21 model names and tier percentages legible at the paper's
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

The retained GPT-5.6 runs contain Codex's combined non-cached-input-plus-output token
count, but not the billing split or cached-input count. The plotted cost is therefore
a consistent comparison estimate rather than reconstructed billing: mean reported
tokens multiplied by a fixed 50% input / 50% output price mix. Cached input is
excluded. The backing CSV records the assumption, prices, pricing date, and official
source URL for every point.

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

Canonical outputs:

- `figures/4c_gpt56_score_vs_cost.pdf`
- `tables/4c_gpt56_score_vs_cost.csv`

## All-model score/cost comparison

`src/all_models_score_vs_cost.py` extends the score-versus-cost view to every
evaluated model except the Qwen Pi-T experiment. To keep the figure readable, only
the xhigh result is retained for each GPT-5.6 variant. Prices are a dated snapshot of
OpenRouter's public, non-batch endpoints. For each model, the selected endpoint is
the one that minimizes estimated cost for that model's observed token mix; Flex is
eligible, and cached tokens use the normal input rate if an endpoint lists no cache
discount. Gemini 3 Pro Preview is retired and absent from the live catalog, so its
last OpenRouter input/output price is paired with a current public cached-input
price. The evaluated Qwen 3.6 27B U-DQ4 model is matched to the cheapest endpoint for
the underlying Qwen 3.6 27B model, currently an FP8 endpoint.

Where the retained data has token categories, cost is computed per run from uncached
input, cached input, and output tokens before averaging. GPT-5.6 retains only a
combined token count, so those three xhigh points use the same fixed 50% input / 50%
output proxy as the focused GPT-5.6 figure. The backing CSV records both methods,
all rates, selected providers and routing tags, model matches, source URLs, and the
2026-08-22 pricing date. Long-context surcharges, storage, tools, future provider
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

The retained analysis joins the original static-audit score, corrected scoped-rerun
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
