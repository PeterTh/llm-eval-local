"""Build the ordered score-tier comparison for the expanded LLM evaluation."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

from matplotlib import colors
import matplotlib.font_manager as font_manager
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = REPOSITORY_ROOT / "data" / "scoring" / "scored_results.csv"
DEFAULT_FIGURE = REPOSITORY_ROOT / "analysis" / "figures" / "8_success_rate_tiers.pdf"
DEFAULT_TABLE = REPOSITORY_ROOT / "analysis" / "tables" / "8_success_rate_tiers.csv"

MODEL_LABELS = {
    "claude-haiku-4.5": "Haiku 4.5",
    "claude-sonnet-4.5": "Sonnet 4.5",
    "claude-opus-4.6": "Opus 4.6",
    "deepseek-v4-flash": "DeepSeek V4 Flash",
    "gemini-3-pro-preview": "Gemini 3 Pro",
    "gpt-4.1": "GPT-4.1",
    "gpt-5-mini": "GPT-5 Mini",
    "gpt-5.2": "GPT-5.2",
    "gpt-5.2-codex": "GPT-5.2 Codex",
    "gpt-5.6-luna-low": "GPT-5.6 Luna Low",
    "gpt-5.6-luna-medium": "GPT-5.6 Luna Medium",
    "gpt-5.6-luna-xhigh": "GPT-5.6 Luna XHigh",
    "gpt-5.6-sol-low": "GPT-5.6 Sol Low",
    "gpt-5.6-sol-medium": "GPT-5.6 Sol Medium",
    "gpt-5.6-sol-xhigh": "GPT-5.6 Sol XHigh",
    "gpt-5.6-terra-low": "GPT-5.6 Terra Low",
    "gpt-5.6-terra-medium": "GPT-5.6 Terra Medium",
    "gpt-5.6-terra-xhigh": "GPT-5.6 Terra XHigh",
    "qwen-3.6-27B-udq4": "Qwen 3.6 27B U-DQ4",
    "qwen-3.6-27B-udq4-pi-t": "Qwen 3.6 27B U-DQ4 Pi-T",
    "qwen3.7-plus": "Qwen 3.7 Plus",
}

TIERS = (
    ("invalid", "Invalid (0-4)", "#d62728", "--"),
    ("no_speedup", "No Speedup (5)", "#ff7f0e", "//"),
    ("ok", "OK (6-7)", "#1f77b4", "\\\\"),
    ("good_top", "Good-Top (8-10)", "#2ca02c", "||"),
)

FIXED_PDF_TIMESTAMP = datetime(2026, 8, 22, tzinfo=timezone.utc)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--figure", type=Path, default=DEFAULT_FIGURE)
    parser.add_argument("--table", type=Path, default=DEFAULT_TABLE)
    return parser.parse_args()


def tier_for_score(score: int) -> str:
    if score <= 4:
        return "invalid"
    if score == 5:
        return "no_speedup"
    if score <= 7:
        return "ok"
    return "good_top"


def load_and_validate(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    required = {"model", "overall_score"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"missing required columns: {', '.join(sorted(missing))}")
    if frame.empty:
        raise ValueError("input dataset is empty")
    if frame[list(required)].isna().any().any():
        raise ValueError("model and overall_score must not contain null values")
    if (frame["model"].astype(str).str.strip() == "").any():
        raise ValueError("model identifiers must not be empty")

    numeric_scores = pd.to_numeric(frame["overall_score"], errors="raise")
    if not np.allclose(numeric_scores, np.round(numeric_scores)):
        raise ValueError("overall_score must contain integers")
    if not numeric_scores.between(0, 10).all():
        raise ValueError("overall_score must be within the inclusive range 0-10")
    frame = frame.copy()
    frame["overall_score"] = numeric_scores.astype(int)

    observation_counts = frame.groupby("model", sort=False).size()
    if observation_counts.nunique() != 1:
        detail = ", ".join(f"{model}={count}" for model, count in observation_counts.items())
        raise ValueError(f"models do not have a balanced observation count: {detail}")

    unknown_models = sorted(set(frame["model"]) - set(MODEL_LABELS))
    if unknown_models:
        raise ValueError(
            "MODEL_LABELS is missing display names for: " + ", ".join(unknown_models)
        )
    return frame


def aggregate(frame: pd.DataFrame) -> pd.DataFrame:
    scored = frame.assign(tier=frame["overall_score"].map(tier_for_score))
    tier_keys = [tier[0] for tier in TIERS]
    counts = (
        scored.groupby(["model", "tier"], observed=True)
        .size()
        .unstack(fill_value=0)
        .reindex(columns=tier_keys, fill_value=0)
    )
    model_stats = frame.groupby("model")["overall_score"].agg(
        run_count="size", mean_score="mean"
    )
    summary = model_stats.join(counts).sort_index(kind="stable").sort_values(
        ["mean_score"], ascending=True, kind="stable"
    )
    summary.insert(0, "rank", np.arange(1, len(summary) + 1))
    summary.insert(1, "model_label", [MODEL_LABELS[model] for model in summary.index])
    for key in tier_keys:
        summary[f"{key}_pct"] = summary[key] / summary["run_count"] * 100.0
    return summary


def write_table(summary: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = ["rank", "model_label", "run_count", "mean_score"]
    for key, _, _, _ in TIERS:
        columns.extend([key, f"{key}_pct"])
    output = summary.reset_index(names="model")
    output = output[["rank", "model", *columns[1:]]]
    output.to_csv(path, index=False, float_format="%.6f", lineterminator="\n")


def configure_plot_style() -> None:
    candidates = ["Roboto Condensed", "Arial Narrow", "DejaVu Sans"]
    available = {font.name for font in font_manager.fontManager.ttflist}
    chosen = next((font for font in candidates if font in available), "DejaVu Sans")
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": [chosen, "DejaVu Sans"],
            "font.size": 9,
            "axes.labelsize": 10,
            "xtick.labelsize": 8,
            "ytick.labelsize": 8,
            "legend.fontsize": 8.5,
            "hatch.linewidth": 0.8,
            "pdf.fonttype": 42,
        }
    )


def draw_figure(summary: pd.DataFrame, path: Path) -> None:
    configure_plot_style()
    height = max(5.5, 0.27 * len(summary) + 1.2)
    figure, axis = plt.subplots(figsize=(6.5, height))
    y_positions = np.arange(len(summary))
    left = np.zeros(len(summary))

    for key, label, color, hatch in TIERS:
        values = summary[f"{key}_pct"].to_numpy()
        bars = axis.barh(
            y_positions,
            values,
            left=left,
            height=0.78,
            label=label,
            color=color,
            edgecolor="black",
            linewidth=0.3,
            hatch=hatch,
        )
        for bar in bars:
            bar._hatch_color = colors.to_rgba("white", 0.55)
            bar.stale = True
        for row, value in enumerate(values):
            if value > 8:
                axis.text(
                    left[row] + value / 2,
                    y_positions[row],
                    f"{value:.0f}%",
                    ha="center",
                    va="center",
                    fontsize=7.2,
                    bbox={
                        "boxstyle": "round,pad=0.17",
                        "facecolor": colors.to_rgba("white", 0.72),
                        "edgecolor": "none",
                    },
                )
        left += values

    axis.set_yticks(y_positions)
    axis.set_yticklabels(summary["model_label"])
    axis.invert_yaxis()
    axis.set_ylim(len(summary) - 0.5, -0.5)
    axis.set_xlim(0, 100)
    axis.set_xticks(np.arange(0, 101, 20))
    axis.set_xlabel("Percentage of Runs")
    axis.set_ylabel("Model (weakest to best)")
    axis.grid(axis="x", color="#d9d9d9", linewidth=0.45, zorder=0)
    axis.set_axisbelow(True)
    figure.legend(
        loc="upper center",
        bbox_to_anchor=(0.5, 0.995),
        ncol=4,
        frameon=False,
        handlelength=2.6,
        columnspacing=1.15,
    )
    figure.subplots_adjust(left=0.315, right=0.985, bottom=0.09, top=0.945)

    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(
        path,
        format="pdf",
        metadata={
            "Title": "Tiered success rates per LLM",
            "Author": "Peter Thoman and Philipp Gschwandtner",
            "Subject": "Expanded local validation and benchmark results",
            "Keywords": "LLM, parallelization, success rate, score tiers",
            "Creator": "analysis/src/success_rate_tiers.py",
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
        f"across {len(summary)} models."
    )


if __name__ == "__main__":
    main()
