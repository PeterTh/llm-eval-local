"""Descriptive, same-workload native/OpenCode comparisons with common frozen prices."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import median

import pandas as pd

from all_models_score_vs_cost import MODELS, aggregate, load_and_validate


ROOT = Path(__file__).resolve().parents[2]
NATIVE = "gpt-6.1-sol-medium"
OPENCODE = "gpt-6.1-sol-oc-medium"
PROFILES = (NATIVE, OPENCODE)
BATCHES = {NATIVE: "20261006-204623", OPENCODE: "20261017-192226"}
COMPARISONS = {
    "sol61": {"profiles": PROFILES, "batches": BATCHES},
    "luna6": {
        "profiles": ("gpt-6-luna-medium", "gpt-6-luna-oc-medium"),
        "batches": {"gpt-6-luna-medium": "20260929-135931", "gpt-6-luna-oc-medium": "20261018-224015"},
    },
    "haiku55": {
        "profiles": ("claude-haiku-5.5-cc-medium", "claude-haiku-5.5-oc-medium"),
        "batches": {"claude-haiku-5.5-cc-medium": "20261012-111947", "claude-haiku-5.5-oc-medium": "20261025-170040"},
        "native_key": "claude_code",
        "native_label": "Claude Code",
    },
}


def successful(value: object) -> bool:
    if str(value).lower() not in ("true", "false", "nan", ""):
        raise ValueError(f"unexpected benchmark success flag: {value!r}")
    return str(value).lower() == "true"


def compare(frame: pd.DataFrame, comparison: str = "sol61", context_usage: dict | None = None) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    """All-run outcomes stay separate from success-conditional runtime ratios."""
    native, opencode = profiles = COMPARISONS[comparison]["profiles"]
    native_key = COMPARISONS[comparison].get("native_key", "codex")
    ratio_key = f"opencode_over_{native_key}_runtime"
    frame = frame[frame["model"].isin(profiles)].copy()
    if set(frame["model"]) != set(profiles):
        raise ValueError("both harness profiles are required")
    keys = ["benchmark", "par_type", "run"]
    scopes = []
    for model in profiles:
        group = frame[frame["model"] == model]
        scope = list(group[keys].itertuples(index=False, name=None))
        if len(scope) != len(set(scope)):
            raise ValueError("duplicate observation")
        scopes.append(set(scope))
    if scopes[0] != scopes[1]:
        raise ValueError("harness workload/repetition scopes differ")
    for column in ("total_time", "total_tokens", "overall_score", "validation_status"):
        frame[column] = pd.to_numeric(frame[column], errors="raise")
        if not frame[column].map(math.isfinite).all():
            raise ValueError(f"missing or nonfinite {column}")
    frame["successful"] = frame["benchmark_success"].map(successful)
    frame["benchmark_median_time"] = pd.to_numeric(frame["benchmark_median_time"], errors="coerce")
    times = frame.loc[frame["successful"], "benchmark_median_time"]
    if not times.map(math.isfinite).all() or not (times > 0).all():
        raise ValueError("successful measurements need positive finite medians")
    rates = ("input_price", "cached_input_price", "output_price", "context_threshold_tokens",
             "long_input_price", "long_cached_input_price", "long_output_price")
    if any(MODELS[native].get(key) != MODELS[opencode].get(key) for key in rates):
        raise ValueError("harness comparison requires common frozen rates")

    summaries = []
    for backend in ("all", *sorted(frame["par_type"].unique())):
        selected = frame if backend == "all" else frame[frame["par_type"] == backend]
        costs = aggregate(selected, context_usage=context_usage).set_index("model")
        for model in profiles:
            group = selected[selected["model"] == model]
            summaries.append({
                "model": model, "backend": backend, "programs": len(group),
                "validation_passed": int((group["validation_status"] == 5).sum()),
                "benchmark_successful": int(group["successful"].sum()),
                "timing_fixed": int(group["timing_fixed"].map(lambda value: str(value).lower() == "true").sum()),
                "mean_overall_score": group["overall_score"].mean(),
                "mean_generation_seconds": group["total_time"].mean(),
                "median_generation_seconds": group["total_time"].median(),
                "mean_total_tokens": group["total_tokens"].mean(),
                "mean_input_tokens": costs.loc[model, "mean_input_tokens"],
                "mean_cached_input_tokens": costs.loc[model, "mean_cached_input_tokens"],
                "mean_output_tokens": costs.loc[model, "mean_output_tokens"],
                "estimated_cost_usd_per_run": costs.loc[model, "estimated_cost_usd_per_run"],
            })

    cells = []
    for (benchmark, backend), group in frame.groupby(["benchmark", "par_type"], sort=True):
        cell = {"benchmark": benchmark, "backend": backend}
        for name, model in ((native_key, native), ("opencode", opencode)):
            entries = group[group["model"] == model]
            measured = entries[entries["successful"]]
            cell[f"{name}_programs"] = len(entries)
            cell[f"{name}_successful"] = len(measured)
            cell[f"{name}_mean_score"] = entries["overall_score"].mean()
            cell[f"{name}_median_ms"] = median(measured["benchmark_median_time"]) if len(measured) else None
        denominator, numerator = cell[f"{native_key}_median_ms"], cell["opencode_median_ms"]
        cell[ratio_key] = numerator / denominator if numerator is not None and denominator is not None else None
        cell["all_programs_successful"] = all(cell[f"{name}_successful"] == cell[f"{name}_programs"] for name in (native_key, "opencode"))
        cells.append(cell)

    runtime = {}
    for backend in ("all", *sorted(frame["par_type"].unique())):
        selection = [cell for cell in cells if backend == "all" or cell["backend"] == backend]
        runtime[backend] = {}
        for policy, eligible in (
            ("both_have_success", [cell for cell in selection if cell[ratio_key] is not None]),
            ("all_programs_successful", [cell for cell in selection if cell["all_programs_successful"]]),
        ):
            ratios = [cell[ratio_key] for cell in eligible]
            runtime[backend][policy] = {
                "cells": len(ratios),
                f"geometric_mean_{ratio_key}": math.exp(sum(map(math.log, ratios)) / len(ratios)) if ratios else None,
                "opencode_faster_cells": sum(value < 1 for value in ratios),
                f"{native_key}_faster_cells": sum(value > 1 for value in ratios),
                "equal_cells": sum(value == 1 for value in ratios),
            }
    return pd.DataFrame(summaries), pd.DataFrame(cells), runtime


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--comparison", choices=COMPARISONS, default="sol61")
    parser.add_argument("--input", type=Path, default=ROOT / "release/scored_results.csv")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "analysis/tables")
    args = parser.parse_args()
    profiles = COMPARISONS[args.comparison]["profiles"]
    batches = COMPARISONS[args.comparison]["batches"]
    native_label = COMPARISONS[args.comparison].get("native_label", "Codex")
    frame = load_and_validate(args.input)
    selected = frame[frame["model"].isin(profiles)]
    for model in profiles:
        group = selected[selected["model"] == model]
        if len(group) != 220 or set(group["source_batch"]) != {batches[model]}:
            raise ValueError(f"unexpected campaign scope for {model}")
        if len(group.groupby(["benchmark", "par_type"])) != 44 or not (group.groupby(["benchmark", "par_type"]).size() == 5).all():
            raise ValueError("expected 44 cells with five generated programs each")
    summary, cells, runtime = compare(selected, comparison=args.comparison)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    prefix = args.output_dir / f"{args.comparison}_harness"
    summary.to_csv(f"{prefix}_summary.csv", index=False, float_format="%.9f", lineterminator="\n")
    cells.to_csv(f"{prefix}_cells.csv", index=False, float_format="%.9f", lineterminator="\n")
    evidence = {
        "schema_version": 1,
        "input": str(args.input.relative_to(ROOT)) if args.input.is_relative_to(ROOT) else str(args.input),
        "input_sha256": hashlib.sha256(args.input.read_bytes()).hexdigest(),
        "source_batches": batches,
        "programs_per_profile": 220,
        "runtime_unit": "median of the successful independently generated programs' five-measurement medians in each benchmark/backend cell",
        "runtime_ratio_direction": f"OpenCode / {native_label}; below one means OpenCode programs are faster",
        "weighting": "equal weight per benchmark/backend cell, not per millisecond or per successful program",
        "outcomes": "validation, successful benchmark count, mean joint score, generation time, tokens and API-rate cost include all 220 programs per profile",
        "runtime_conditioning": "both-have-success includes only cells with at least one successful program in each harness; all-programs-successful is a stricter sensitivity view",
        "interpretation": "descriptive comparison of complete stock harness setups; independent generation, different provider routes and campaign dates, and mutable model aliases do not identify a pure causal harness effect",
        "cost": ("same frozen Anthropic rates in both request-context tiers; cache creation at ordinary input rates; not actual subscription charges"
                 if args.comparison == "haiku55" else "same frozen OpenAI Flex token rates; not actual subscription charges"),
        "runtime": runtime,
    }
    Path(f"{prefix}_context.json").write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n")
    print(summary.to_string(index=False))
    print(json.dumps(runtime["all"], indent=2))


if __name__ == "__main__":
    main()
