# Analysis

Analysis reads only the versioned files under `data/`. Reusable source belongs in
`src/`, optional output-stripped notebooks in `notebooks/`, final machine-readable
tables in `tables/`, and final figures in `figures/`.

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

The checked-in outputs consume release `local-eval-2026-08-22` at commit `bfb6df4` and
`data/scoring/scored_results.csv` (SHA-256
`2f0a76118c836b326a99b877b86746a6bfeeb3986061e07f1d8bc1fdb451e76c`).

Install the locked direct dependencies and rebuild with:

```bash
python -m pip install -r analysis/requirements.txt
python analysis/src/success_rate_tiers.py
```

Canonical outputs:

- `figures/8_success_rate_tiers.pdf`
- `tables/8_success_rate_tiers.csv`

Focused follow-up notes:

- `notes/2026-08-22-sol-xhigh-mpi-simd-classification.md` documents why the larger
  invalid segment for GPT-5.6 Sol xhigh is primarily an MPI/OpenMP-SIMD classification
  boundary rather than a general increase in later-stage validation failures.

Do not commit notebook cell output, caches, serialized interpreter workspaces, or
intermediate datasets. Prefer CSV for tables and PDF for vector figures; retain one
canonical format unless the publication toolchain requires another.
