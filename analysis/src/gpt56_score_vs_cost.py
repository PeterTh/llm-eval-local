"""Plot GPT-5.6 mean score against a current-price API cost estimate."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.font_manager as font_manager
import matplotlib.pyplot as plt
from matplotlib.ticker import FixedLocator, FuncFormatter
import numpy as np
import pandas as pd


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = REPOSITORY_ROOT / "data" / "scoring" / "scored_results.csv"
DEFAULT_FIGURE = REPOSITORY_ROOT / "analysis" / "figures" / "4c_gpt56_score_vs_cost.pdf"
DEFAULT_TABLE = REPOSITORY_ROOT / "analysis" / "tables" / "4c_gpt56_score_vs_cost.csv"

PRICING_AS_OF = "2026-08-22"
ASSUMED_OUTPUT_SHARE = 0.5
FIXED_PDF_TIMESTAMP = datetime(2026, 8, 22, tzinfo=timezone.utc)

# Standard API prices in USD per million tokens. These values intentionally remain
# versioned with the analysis rather than being fetched at build time.
# Sources:
# https://developers.openai.com/api/docs/models/gpt-5.6-sol
# https://developers.openai.com/api/docs/models/gpt-5.6-terra
# https://developers.openai.com/api/docs/models/gpt-5.6-luna
VARIANTS = {
    "luna": {
        "label": "GPT-5.6 Luna",
        "color": "#2060a0",
        "marker": "D",
        "input_price": 0.20,
        "cached_input_price": 0.02,
        "output_price": 1.20,
        "pricing_url": "https://developers.openai.com/api/docs/models/gpt-5.6-luna",
    },
    "terra": {
        "label": "GPT-5.6 Terra",
        "color": "#2d8e2d",
        "marker": "s",
        "input_price": 2.00,
        "cached_input_price": 0.20,
        "output_price": 12.00,
        "pricing_url": "https://developers.openai.com/api/docs/models/gpt-5.6-terra",
    },
    "sol": {
        "label": "GPT-5.6 Sol",
        "color": "#e8883a",
        "marker": "^",
        "input_price": 4.00,
        "cached_input_price": 0.40,
        "output_price": 20.00,
        "pricing_url": "https://developers.openai.com/api/docs/models/gpt-5.6-sol",
    },
}
VARIANT_ORDER = ("luna", "terra", "sol")
EFFORT_ORDER = ("low", "medium", "xhigh")
EFFORT_LABELS = {"low": "Low", "medium": "Med.", "xhigh": "XHigh"}
EXPECTED_MODELS = {
    f"gpt-5.6-{variant}-{effort}"
    for variant in VARIANT_ORDER
    for effort in EFFORT_ORDER
}

# Offsets are in display points and keep the compact paper-sized figure legible.
LABEL_OFFSETS = {
    ("luna", "low"): (7, -3),
    ("luna", "medium"): (7, -3),
    ("luna", "xhigh"): (7, 2),
    ("terra", "low"): (-7, -3),
    ("terra", "medium"): (-7, 3),
    ("terra", "xhigh"): (-7, -3),
    ("sol", "low"): (7, -3),
    ("sol", "medium"): (-7, 3),
    ("sol", "xhigh"): (-7, 3),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--figure", type=Path, default=DEFAULT_FIGURE)
    parser.add_argument("--table", type=Path, default=DEFAULT_TABLE)
    return parser.parse_args()


def load_and_validate(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    required = {"model", "overall_score", "total_tokens"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"missing required columns: {', '.join(sorted(missing))}")

    gpt56 = frame[frame["model"].astype(str).str.startswith("gpt-5.6-")].copy()
    observed_models = set(gpt56["model"])
    if observed_models != EXPECTED_MODELS:
        missing_models = sorted(EXPECTED_MODELS - observed_models)
        extra_models = sorted(observed_models - EXPECTED_MODELS)
        raise ValueError(
            "unexpected GPT-5.6 model set: "
            f"missing={missing_models or 'none'}, extra={extra_models or 'none'}"
        )

    if gpt56[list(required)].isna().any().any():
        raise ValueError("GPT-5.6 model, score, and total-token values must be complete")
    gpt56["overall_score"] = pd.to_numeric(gpt56["overall_score"], errors="raise")
    gpt56["total_tokens"] = pd.to_numeric(gpt56["total_tokens"], errors="raise")
    if not gpt56["overall_score"].between(0, 10).all():
        raise ValueError("overall_score must be within the inclusive range 0-10")
    if not (gpt56["total_tokens"] > 0).all():
        raise ValueError("total_tokens must be positive")

    counts = gpt56.groupby("model", sort=False).size()
    if counts.nunique() != 1:
        detail = ", ".join(f"{model}={count}" for model, count in counts.items())
        raise ValueError(f"models do not have a balanced observation count: {detail}")

    split_columns = {"input_tokens", "output_tokens", "cached_tokens"}
    if split_columns <= set(gpt56.columns) and gpt56[list(split_columns)].notna().any().any():
        raise ValueError(
            "GPT-5.6 token splits are now present; replace the fixed-mix proxy with "
            "exact per-run pricing before regenerating this figure"
        )
    return gpt56


def aggregate(frame: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for model, group in frame.groupby("model", sort=False):
        prefix, variant, effort = model.rsplit("-", 2)
        if prefix != "gpt-5.6":
            raise ValueError(f"cannot parse GPT-5.6 model identifier: {model}")
        config = VARIANTS[variant]
        mean_tokens = group["total_tokens"].mean()
        effective_price = (
            (1.0 - ASSUMED_OUTPUT_SHARE) * config["input_price"]
            + ASSUMED_OUTPUT_SHARE * config["output_price"]
        )
        rows.append(
            {
                "model": model,
                "model_label": config["label"],
                "variant": variant,
                "effort": effort,
                "effort_label": EFFORT_LABELS[effort],
                "run_count": len(group),
                "mean_overall_score": group["overall_score"].mean(),
                "mean_reported_tokens": mean_tokens,
                "assumed_input_share": 1.0 - ASSUMED_OUTPUT_SHARE,
                "assumed_output_share": ASSUMED_OUTPUT_SHARE,
                "input_price_usd_per_million": config["input_price"],
                "cached_input_price_usd_per_million": config["cached_input_price"],
                "output_price_usd_per_million": config["output_price"],
                "effective_price_usd_per_million": effective_price,
                "estimated_cost_usd_per_run": mean_tokens * effective_price / 1_000_000,
                "pricing_as_of": PRICING_AS_OF,
                "pricing_source_url": config["pricing_url"],
                "cost_method": "50% input + 50% output price applied to mean reported tokens; cached input excluded",
            }
        )
    summary = pd.DataFrame(rows)
    summary["variant"] = pd.Categorical(
        summary["variant"], categories=VARIANT_ORDER, ordered=True
    )
    summary["effort"] = pd.Categorical(
        summary["effort"], categories=EFFORT_ORDER, ordered=True
    )
    return summary.sort_values(["variant", "effort"], kind="stable").reset_index(drop=True)


def write_table(summary: pd.DataFrame, path: Path) -> None:
    output = summary.copy()
    output["variant"] = output["variant"].astype(str)
    output["effort"] = output["effort"].astype(str)
    path.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(path, index=False, float_format="%.6f", lineterminator="\n")


def configure_plot_style() -> None:
    required_font = "Roboto Condensed"
    available = {font.name for font in font_manager.fontManager.ttflist}
    if required_font not in available:
        for font_path in font_manager.findSystemFonts():
            compact_name = Path(font_path).stem.lower().replace("-", "").replace("_", "")
            if "robotocondensed" not in compact_name:
                continue
            font_manager.fontManager.addfont(font_path)
        available = {font.name for font in font_manager.fontManager.ttflist}
    if required_font not in available:
        raise RuntimeError(
            "Roboto Condensed is required to reproduce the paper figure styling"
        )
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": [required_font],
            "font.size": 10,
            "axes.labelsize": 11,
            "xtick.labelsize": 9,
            "ytick.labelsize": 9,
            "legend.fontsize": 8.5,
            "pdf.fonttype": 42,
        }
    )


def _format_cost(value: float, _position: float) -> str:
    if value < 0.1:
        return f"${value:.2f}"
    if value < 1:
        return f"${value:.1f}"
    return f"${value:.0f}"


def draw_figure(summary: pd.DataFrame, path: Path) -> None:
    configure_plot_style()
    figure, axis = plt.subplots(figsize=(4.8, 3.35))

    for variant in VARIANT_ORDER:
        config = VARIANTS[variant]
        series = summary[summary["variant"] == variant]
        x_values = series["estimated_cost_usd_per_run"].to_numpy()
        y_values = series["mean_overall_score"].to_numpy()
        axis.plot(
            x_values,
            y_values,
            color=config["color"],
            linewidth=1.5,
            alpha=0.85,
            zorder=2,
        )
        axis.scatter(
            x_values,
            y_values,
            s=105,
            color=config["color"],
            marker=config["marker"],
            edgecolor="black",
            linewidth=0.8,
            zorder=3,
            label=config["label"],
        )
        for row in series.itertuples(index=False):
            offset_x, offset_y = LABEL_OFFSETS[(variant, str(row.effort))]
            horizontal_alignment = "right" if offset_x < 0 else "left"
            axis.annotate(
                row.effort_label,
                (row.estimated_cost_usd_per_run, row.mean_overall_score),
                xytext=(offset_x, offset_y),
                textcoords="offset points",
                ha=horizontal_alignment,
                va="center",
                fontsize=8.5,
            )

    axis.set_xscale("log")
    axis.set_xlim(0.016, 1.7)
    axis.set_ylim(5.5, 8.55)
    axis.xaxis.set_major_locator(FixedLocator([0.02, 0.05, 0.1, 0.2, 0.5, 1.0]))
    axis.xaxis.set_major_formatter(FuncFormatter(_format_cost))
    axis.set_yticks(np.arange(5.5, 8.6, 0.5))
    axis.set_xlabel("Estimated API Cost per Run (USD, log scale)")
    axis.set_ylabel("Mean Overall Score")
    axis.grid(alpha=0.3, which="major")
    axis.grid(alpha=0.12, which="minor", axis="x")
    axis.legend(loc="lower right", frameon=False)
    figure.tight_layout()

    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(
        path,
        format="pdf",
        metadata={
            "Title": "GPT-5.6 mean score versus estimated API cost",
            "Author": "Peter Thoman and Philipp Gschwandtner",
            "Subject": "Expanded local evaluation results",
            "Keywords": "GPT-5.6, score, API cost, reasoning effort",
            "Creator": "analysis/src/gpt56_score_vs_cost.py",
            "Producer": f"Matplotlib {matplotlib.__version__}",
            "CreationDate": FIXED_PDF_TIMESTAMP,
            "ModDate": FIXED_PDF_TIMESTAMP,
        },
    )
    plt.close(figure)


def main() -> None:
    args = parse_args()
    frame = load_and_validate(args.input)
    summary = aggregate(frame)
    write_table(summary, args.table)
    draw_figure(summary, args.figure)
    print(
        f"Wrote {args.figure} and {args.table} from {len(frame):,} rows "
        f"across {len(summary)} GPT-5.6 model/effort combinations."
    )


if __name__ == "__main__":
    main()
