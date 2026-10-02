"""Plot mean score against a current-price API cost estimate for all models."""

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
DEFAULT_INPUT = REPOSITORY_ROOT / "release" / "scored_results.csv"
DEFAULT_FIGURE = REPOSITORY_ROOT / "analysis" / "figures" / "4d_all_models_score_vs_cost.pdf"
DEFAULT_TABLE = REPOSITORY_ROOT / "analysis" / "tables" / "4d_all_models_score_vs_cost.csv"

PRICING_AS_OF = "2026-08-22"
OPENROUTER_CATALOG_URL = "https://openrouter.ai/api/v1/models"
FIXED_PDF_TIMESTAMP = datetime(2026, 8, 22, tzinfo=timezone.utc)
PRICING_SELECTION_POLICY = (
    "lowest estimated cost among live non-batch OpenRouter endpoints for the "
    "observed token mix; cached tokens use the input rate when no cache-read "
    "rate is listed"
)

# Non-batch API prices in USD per million tokens. For each model, the selected
# rate is the live OpenRouter endpoint that minimizes estimated cost for that
# model's observed token mix. Flex endpoints are eligible. Gemini 3 Pro Preview
# is no longer present in the live catalog; its last OpenRouter rate is combined
# with a current public source for the cached-input rate.
MODELS = {
    "gpt-6-sol-medium": {
        "label": "GPT-6 Sol Medium", "color": "#216c47", "marker": "o",
        "pricing_as_of": "2026-10-02", "pricing_model_id": "openai/gpt-6-sol",
        "input_price": 1.0, "cached_input_price": 0.1, "output_price": 5.0,
        "pricing_provider": "OpenAI", "pricing_provider_tag": "openai/flex", "pricing_quantization": "unknown",
        "pricing_source_kind": "official OpenAI model pricing",
        "pricing_selection_policy": "lowest published non-batch OpenAI processing tier (Flex); historical profiles unchanged",
        "pricing_catalog_url": "https://developers.openai.com/api/docs/pricing",
        "pricing_endpoint_url": "https://developers.openai.com/api/docs/models/gpt-6-sol",
        "pricing_source_url": "https://developers.openai.com/api/docs/models/gpt-6-sol",
    },
    "gpt-6-luna-medium": {
        "label": "GPT-6 Luna Medium", "color": "#73a942", "marker": "s",
        "pricing_as_of": "2026-10-02", "pricing_model_id": "openai/gpt-6-luna",
        "input_price": 0.05, "cached_input_price": 0.005, "output_price": 0.25,
        "pricing_provider": "OpenAI", "pricing_provider_tag": "openai/flex", "pricing_quantization": "unknown",
        "pricing_source_kind": "official OpenAI model pricing",
        "pricing_selection_policy": "lowest published non-batch OpenAI processing tier (Flex); historical profiles unchanged",
        "pricing_catalog_url": "https://developers.openai.com/api/docs/pricing",
        "pricing_endpoint_url": "https://developers.openai.com/api/docs/models/gpt-6-luna",
        "pricing_source_url": "https://developers.openai.com/api/docs/models/gpt-6-luna",
    },
    "gpt-6-astra-medium": {
        "label": "GPT-6 Astra Medium", "color": "#123d6a", "marker": "D",
        "pricing_as_of": "2026-10-02", "pricing_model_id": "openai/gpt-6-astra",
        "input_price": 5.0, "cached_input_price": 0.5, "output_price": 25.0,
        "pricing_provider": "OpenAI", "pricing_provider_tag": "openai/flex", "pricing_quantization": "unknown",
        "pricing_source_kind": "official OpenAI model pricing",
        "pricing_selection_policy": "lowest published non-batch OpenAI processing tier (Flex); historical profiles unchanged",
        "pricing_catalog_url": "https://developers.openai.com/api/docs/pricing",
        "pricing_endpoint_url": "https://developers.openai.com/api/docs/models/gpt-6-astra",
        "pricing_source_url": "https://developers.openai.com/api/docs/models/gpt-6-astra",
    },
    "claude-fable-5-cc-medium": {
        "label": "Fable 5 Medium", "color": "#903820", "marker": "D",
        "pricing_as_of": "2026-09-29", "pricing_model_id": "anthropic/claude-fable-5",
        "input_price": 10.0, "cached_input_price": 1.0, "output_price": 50.0,
        "pricing_provider": "Anthropic", "pricing_provider_tag": "anthropic", "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/anthropic/claude-5-fable-20260609/endpoints",
        "pricing_source_url": "https://openrouter.ai/anthropic/claude-fable-5",
    },
    "claude-opus-5-cc-medium": {
        "label": "Opus 5 Medium", "color": "#bd5630", "marker": "^",
        "pricing_as_of": "2026-09-29", "pricing_model_id": "anthropic/claude-opus-5",
        "input_price": 5.0, "cached_input_price": 0.5, "output_price": 25.0,
        "pricing_provider": "Anthropic", "pricing_provider_tag": "anthropic", "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/anthropic/claude-opus-5/endpoints",
        "pricing_source_url": "https://openrouter.ai/anthropic/claude-opus-5",
    },
    "claude-sonnet-5-cc-medium": {
        "label": "Sonnet 5 Medium", "color": "#db9966", "marker": "s",
        "pricing_as_of": "2026-09-29", "pricing_model_id": "anthropic/claude-sonnet-5",
        "input_price": 2.0, "cached_input_price": 0.2, "output_price": 10.0,
        "pricing_provider": "Anthropic", "pricing_provider_tag": "anthropic", "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/anthropic/claude-sonnet-5/endpoints",
        "pricing_source_url": "https://openrouter.ai/anthropic/claude-sonnet-5",
    },
    "claude-haiku-4.5": {
        "label": "Haiku 4.5",
        "color": "#a8c8e8",
        "marker": "^",
        "pricing_model_id": "anthropic/claude-haiku-4.5",
        "input_price": 1.0,
        "cached_input_price": 0.1,
        "output_price": 5.0,
        "pricing_provider": "Anthropic",
        "pricing_provider_tag": "anthropic",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/anthropic/claude-4.5-haiku-20251001/endpoints",
        "pricing_source_url": "https://openrouter.ai/anthropic/claude-haiku-4.5",
    },
    "claude-opus-4.6": {
        "label": "Opus 4.6",
        "color": "#2060a0",
        "marker": "D",
        "pricing_model_id": "anthropic/claude-opus-4.6",
        "input_price": 5.0,
        "cached_input_price": 0.5,
        "output_price": 25.0,
        "pricing_provider": "Azure",
        "pricing_provider_tag": "azure/global",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/anthropic/claude-4.6-opus-20260205/endpoints",
        "pricing_source_url": "https://openrouter.ai/anthropic/claude-opus-4.6",
    },
    "claude-sonnet-4.5": {
        "label": "Sonnet 4.5",
        "color": "#5b9bd5",
        "marker": "s",
        "pricing_model_id": "anthropic/claude-sonnet-4.5",
        "input_price": 3.0,
        "cached_input_price": 0.3,
        "output_price": 15.0,
        "pricing_provider": "Google",
        "pricing_provider_tag": "google-vertex/global",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/anthropic/claude-4.5-sonnet-20250929/endpoints",
        "pricing_source_url": "https://openrouter.ai/anthropic/claude-sonnet-4.5",
    },
    "deepseek-v4-flash": {
        "label": "DeepSeek V4 Flash",
        "color": "#7b5ea7",
        "marker": "*",
        "pricing_model_id": "deepseek/deepseek-v4-flash",
        "input_price": 0.05866,
        "cached_input_price": 0.011732,
        "output_price": 0.11732,
        "pricing_provider": "StreamLake",
        "pricing_provider_tag": "streamlake/fp8",
        "pricing_quantization": "fp8",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/deepseek/deepseek-v4-flash-20260423/endpoints",
        "pricing_source_url": "https://openrouter.ai/deepseek/deepseek-v4-flash",
    },
    "gemini-3-pro-preview": {
        "label": "Gemini 3 Pro",
        "color": "#e8883a",
        "marker": "h",
        "pricing_model_id": "google/gemini-3-pro-preview",
        "input_price": 2.0,
        "cached_input_price": 0.2,
        "output_price": 12.0,
        "pricing_provider": "Google",
        "pricing_provider_tag": "retired",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "",
        "pricing_source_url": "https://openrouter.ai/google/gemini-3-pro-preview-20251117/providers",
        "secondary_pricing_source_url": "https://marginalhq.com/models/gemini-3-pro",
        "pricing_source_kind": "retired OpenRouter listing plus public cache-rate fallback",
        "pricing_selection_policy": "retired model fallback; no live endpoint available",
    },
    "gpt-4.1": {
        "label": "GPT-4.1",
        "color": "#8c6d5e",
        "marker": "X",
        "pricing_model_id": "openai/gpt-4.1",
        "input_price": 2.0,
        "cached_input_price": 0.5,
        "output_price": 8.0,
        "pricing_provider": "OpenAI",
        "pricing_provider_tag": "openai",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/openai/gpt-4.1-2025-04-14/endpoints",
        "pricing_source_url": "https://openrouter.ai/openai/gpt-4.1",
    },
    "gpt-5-mini": {
        "label": "GPT-5 Mini",
        "color": "#b8a089",
        "marker": "P",
        "pricing_model_id": "openai/gpt-5-mini",
        "input_price": 0.125,
        "cached_input_price": 0.0125,
        "output_price": 1.0,
        "pricing_provider": "OpenAI",
        "pricing_provider_tag": "openai/flex",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/openai/gpt-5-mini-2025-08-07/endpoints",
        "pricing_source_url": "https://openrouter.ai/openai/gpt-5-mini",
    },
    "gpt-5.2": {
        "label": "GPT-5.2",
        "color": "#2d8e2d",
        "marker": "o",
        "pricing_model_id": "openai/gpt-5.2",
        "input_price": 0.875,
        "cached_input_price": 0.0875,
        "output_price": 7.0,
        "pricing_provider": "OpenAI",
        "pricing_provider_tag": "openai/flex",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/openai/gpt-5.2-20251211/endpoints",
        "pricing_source_url": "https://openrouter.ai/openai/gpt-5.2",
    },
    "gpt-5.2-codex": {
        "label": "GPT-5.2 Codex",
        "color": "#6abf69",
        "marker": "v",
        "pricing_model_id": "openai/gpt-5.2-codex",
        "input_price": 1.75,
        "cached_input_price": 0.175,
        "output_price": 14.0,
        "pricing_provider": "Azure",
        "pricing_provider_tag": "azure",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/openai/gpt-5.2-codex-20260114/endpoints",
        "pricing_source_url": "https://openrouter.ai/openai/gpt-5.2-codex",
    },
    "gpt-5.6-luna-xhigh": {
        "label": "GPT-5.6 Luna XHigh",
        "color": "#2060a0",
        "marker": "D",
        "pricing_model_id": "openai/gpt-5.6-luna",
        "input_price": 0.1,
        "cached_input_price": 0.01,
        "output_price": 0.6,
        "pricing_provider": "OpenAI",
        "pricing_provider_tag": "openai/flex",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/openai/gpt-5.6-luna-20260709/endpoints",
        "pricing_source_url": "https://openrouter.ai/openai/gpt-5.6-luna",
    },
    "gpt-5.6-terra-xhigh": {
        "label": "GPT-5.6 Terra XHigh",
        "color": "#2d8e2d",
        "marker": "s",
        "pricing_model_id": "openai/gpt-5.6-terra",
        "input_price": 1.0,
        "cached_input_price": 0.1,
        "output_price": 6.0,
        "pricing_provider": "OpenAI",
        "pricing_provider_tag": "openai/flex",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/openai/gpt-5.6-terra-20260709/endpoints",
        "pricing_source_url": "https://openrouter.ai/openai/gpt-5.6-terra",
    },
    "gpt-5.6-sol-xhigh": {
        "label": "GPT-5.6 Sol XHigh",
        "color": "#e8883a",
        "marker": "^",
        "pricing_model_id": "openai/gpt-5.6-sol",
        "input_price": 1.0,
        "cached_input_price": 0.1,
        "output_price": 5.0,
        "pricing_provider": "OpenAI",
        "pricing_provider_tag": "openai/flex",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/openai/gpt-5.6-sol-20260709/endpoints",
        "pricing_source_url": "https://openrouter.ai/openai/gpt-5.6-sol",
    },
    "qwen-3.6-27B-udq4": {
        "label": "Qwen 3.6 27B U-DQ4",
        "color": "#c44e52",
        "marker": "<",
        "pricing_model_id": "qwen/qwen3.6-27b",
        "input_price": 0.3,
        "cached_input_price": 0.03,
        "output_price": 2.0,
        "pricing_provider": "Chutes",
        "pricing_provider_tag": "chutes/fp8",
        "pricing_quantization": "fp8",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/qwen/qwen3.6-27b-20260422/endpoints",
        "pricing_source_url": "https://openrouter.ai/qwen/qwen3.6-27b",
        "pricing_match_note": "underlying Qwen 3.6 27B FP8 API endpoint used as proxy for evaluated U-DQ4 quantization",
    },
    "qwen3.7-plus": {
        "label": "Qwen 3.7 Plus",
        "color": "#cc78bc",
        "marker": ">",
        "pricing_model_id": "qwen/qwen3.7-plus",
        "input_price": 0.32,
        "cached_input_price": 0.064,
        "output_price": 1.28,
        "pricing_provider": "Alibaba",
        "pricing_provider_tag": "alibaba",
        "pricing_quantization": "unknown",
        "pricing_endpoint_url": "https://openrouter.ai/api/v1/models/qwen/qwen3.7-plus-20260602/endpoints",
        "pricing_source_url": "https://openrouter.ai/qwen/qwen3.7-plus",
    },
}

GPT56_MODELS = {
    "gpt-5.6-luna-xhigh",
    "gpt-5.6-terra-xhigh",
    "gpt-5.6-sol-xhigh",
}
EXCLUDED_MODELS = {
    "qwen-3.6-27B-udq4-pi-t",
    "gpt-5.6-luna-low",
    "gpt-5.6-luna-medium",
    "gpt-5.6-terra-low",
    "gpt-5.6-terra-medium",
    "gpt-5.6-sol-low",
    "gpt-5.6-sol-medium",
}

# Offsets are in display points. These deliberately mirror the paper's manual
# annotation style and keep the dense central cluster readable.
LABEL_OFFSETS = {
    "gpt-6-sol-medium": (-7, 9),
    "gpt-6-luna-medium": (7, -6),
    "gpt-6-astra-medium": (-7, 12),
    "claude-fable-5-cc-medium": (-7, -8),
    "claude-opus-5-cc-medium": (-7, 9),
    "claude-sonnet-5-cc-medium": (7, -9),
    "deepseek-v4-flash": (-7, 4),
    "gpt-5-mini": (7, 0),
    "gpt-5.6-luna-xhigh": (-7, -3),
    "qwen3.7-plus": (-7, 0),
    "claude-haiku-4.5": (-7, 0),
    "gpt-4.1": (7, 0),
    "qwen-3.6-27B-udq4": (-7, 2),
    "gpt-5.2-codex": (-7, -7),
    "gpt-5.2": (-7, -4),
    "gpt-5.6-terra-xhigh": (-7, -9),
    "claude-sonnet-4.5": (7, 8),
    "gemini-3-pro-preview": (7, -7),
    "gpt-5.6-sol-xhigh": (7, -3),
    "claude-opus-4.6": (-7, 0),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--figure", type=Path, default=DEFAULT_FIGURE)
    parser.add_argument("--table", type=Path, default=DEFAULT_TABLE)
    parser.add_argument("--font", type=Path, help="Register an explicit TTF/OTF without installing it")
    return parser.parse_args()


def load_and_validate(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    required = {
        "model",
        "overall_score",
        "input_tokens",
        "output_tokens",
        "cached_tokens",
        "total_tokens",
    }
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"missing required columns: {', '.join(sorted(missing))}")

    observed_models = set(frame["model"])
    expected_models = set(MODELS) | EXCLUDED_MODELS
    if observed_models != expected_models:
        missing_models = sorted(expected_models - observed_models)
        extra_models = sorted(observed_models - expected_models)
        raise ValueError(
            "unexpected source model set: "
            f"missing={missing_models or 'none'}, extra={extra_models or 'none'}"
        )

    selected = frame[frame["model"].isin(MODELS)].copy()
    selected["overall_score"] = pd.to_numeric(
        selected["overall_score"], errors="raise"
    )
    selected["total_tokens"] = pd.to_numeric(
        selected["total_tokens"], errors="coerce"
    )
    if selected[["model", "overall_score"]].isna().any().any():
        raise ValueError("selected model and score values must be complete")
    if not selected["overall_score"].between(0, 10).all():
        raise ValueError("overall_score must be within the inclusive range 0-10")

    counts = selected.groupby("model", sort=False).size()
    if counts.nunique() != 1:
        detail = ", ".join(f"{model}={count}" for model, count in counts.items())
        raise ValueError(f"models do not have a balanced score count: {detail}")

    split_columns = ["input_tokens", "output_tokens", "cached_tokens"]
    numeric_splits = selected[split_columns].apply(pd.to_numeric, errors="coerce")
    complete_splits = numeric_splits.notna().all(axis=1)
    if not complete_splits.groupby(selected["model"]).any().all():
        raise ValueError("each model needs at least one complete token split")
    complete = numeric_splits[complete_splits]
    if not np.isfinite(complete).all().all() or (complete < 0).any().any():
        raise ValueError("token counts must be finite and non-negative")
    if (complete["cached_tokens"] > complete["input_tokens"]).any():
        raise ValueError("cached_tokens must be a subset of input_tokens")

    selected[split_columns] = numeric_splits
    gpt56 = selected[selected["model"].isin(GPT56_MODELS) | selected["model"].str.startswith("gpt-6-")]
    if gpt56[split_columns].isna().any().any():
        raise ValueError("GPT-5.6 requires recovered complete token breakdowns")
    if not (gpt56["total_tokens"] == gpt56["input_tokens"] + gpt56["output_tokens"]).all():
        raise ValueError("GPT-5.6 inclusive token totals disagree")
    if gpt56["total_tokens"].isna().any() or not (gpt56["total_tokens"] > 0).all():
        raise ValueError("GPT-5.6 total-token values must be complete and positive")
    return selected


def aggregate(frame: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for model, group in frame.groupby("model", sort=False):
        config = MODELS[model]
        score_run_count = len(group)
        mean_score = group["overall_score"].mean()

        cost_rows = group.dropna(
            subset=["input_tokens", "output_tokens", "cached_tokens"]
        ).copy()
        for column in ["input_tokens", "output_tokens", "cached_tokens"]:
            cost_rows[column] = pd.to_numeric(cost_rows[column], errors="raise")
        cost_run_count = len(cost_rows)
        per_run_cost = (
            (cost_rows["input_tokens"] - cost_rows["cached_tokens"])
            * config["input_price"]
            + cost_rows["cached_tokens"] * config["cached_input_price"]
            + cost_rows["output_tokens"] * config["output_price"]
        ) / 1_000_000
        estimated_cost = per_run_cost.mean()
        mean_total_tokens = (
            cost_rows["input_tokens"] + cost_rows["output_tokens"]
        ).mean()
        mean_input_tokens = cost_rows["input_tokens"].mean()
        mean_cached_tokens = cost_rows["cached_tokens"].mean()
        mean_output_tokens = cost_rows["output_tokens"].mean()
        effective_price = np.nan
        cost_method = (
            "uncached input, cached input, and output tokens priced separately"
        )

        rows.append(
            {
                "model": model,
                "model_label": config["label"],
                "score_run_count": score_run_count,
                "cost_run_count": cost_run_count,
                "mean_overall_score": mean_score,
                "mean_total_tokens": mean_total_tokens,
                "mean_input_tokens": mean_input_tokens,
                "mean_cached_input_tokens": mean_cached_tokens,
                "mean_output_tokens": mean_output_tokens,
                "input_price_usd_per_million": config["input_price"],
                "cached_input_price_usd_per_million": config[
                    "cached_input_price"
                ],
                "output_price_usd_per_million": config["output_price"],
                "effective_price_usd_per_million": effective_price,
                "estimated_cost_usd_per_run": estimated_cost,
                "pricing_as_of": config.get("pricing_as_of", PRICING_AS_OF),
                "pricing_model_id": config["pricing_model_id"],
                "pricing_provider": config["pricing_provider"],
                "pricing_provider_tag": config["pricing_provider_tag"],
                "pricing_quantization": config["pricing_quantization"],
                "pricing_source_kind": config.get(
                    "pricing_source_kind",
                    "OpenRouter cheapest available endpoint",
                ),
                "pricing_selection_policy": config.get(
                    "pricing_selection_policy", PRICING_SELECTION_POLICY
                ),
                "pricing_catalog_url": config.get("pricing_catalog_url", OPENROUTER_CATALOG_URL),
                "pricing_endpoint_url": config["pricing_endpoint_url"],
                "pricing_source_url": config["pricing_source_url"],
                "secondary_pricing_source_url": config.get(
                    "secondary_pricing_source_url", ""
                ),
                "pricing_match_note": config.get("pricing_match_note", "exact model"),
                "cost_method": cost_method,
            }
        )
    return (
        pd.DataFrame(rows)
        .sort_values("estimated_cost_usd_per_run", kind="stable")
        .reset_index(drop=True)
    )


def write_table(summary: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    summary.to_csv(path, index=False, float_format="%.6f", lineterminator="\n")


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
            "pdf.fonttype": 42,
        }
    )


def _format_cost(value: float, _position: float) -> str:
    if value < 0.01:
        return f"${value:.3f}"
    if value < 0.1:
        return f"${value:.2f}"
    if value < 1:
        return f"${value:.1f}"
    return f"${value:.0f}"


def draw_figure(summary: pd.DataFrame, path: Path) -> None:
    configure_plot_style()
    figure, axis = plt.subplots(figsize=(6.5, 4.0))

    for row in summary.itertuples(index=False):
        config = MODELS[row.model]
        axis.scatter(
            row.estimated_cost_usd_per_run,
            row.mean_overall_score,
            s=105,
            color=config["color"],
            marker=config["marker"],
            edgecolor="black",
            linewidth=0.8,
            zorder=3,
        )
        offset_x, offset_y = LABEL_OFFSETS[row.model]
        axis.annotate(
            row.model_label,
            (row.estimated_cost_usd_per_run, row.mean_overall_score),
            xytext=(offset_x, offset_y),
            textcoords="offset points",
            ha="right" if offset_x < 0 else "left",
            va="center",
            fontsize=8.5,
            zorder=4,
        )

    axis.set_xscale("log")
    axis.set_xlim(min(0.012, summary.estimated_cost_usd_per_run.min() * 0.75), max(1.55, summary.estimated_cost_usd_per_run.max() * 1.8))
    axis.set_ylim(3.1, max(8.6, summary.mean_overall_score.max() + 0.5))
    axis.xaxis.set_major_locator(FixedLocator([0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0]))
    axis.xaxis.set_major_formatter(FuncFormatter(_format_cost))
    axis.set_yticks(np.arange(3.5, 8.6, 0.5))
    axis.set_xlabel("Estimated API Cost per Run (USD, log scale)")
    axis.set_ylabel("Mean Overall Score")
    axis.grid(alpha=0.3, which="major")
    axis.grid(alpha=0.12, which="minor", axis="x")
    figure.tight_layout()

    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(
        path,
        format="pdf",
        metadata={
            "Title": "Mean score versus estimated API cost for all evaluated models",
            "Author": "Peter Thoman and Philipp Gschwandtner",
            "Subject": "Expanded local evaluation results",
            "Keywords": "LLM evaluation, score, API cost, OpenRouter",
            "Creator": "analysis/src/all_models_score_vs_cost.py",
            "Producer": f"Matplotlib {matplotlib.__version__}",
            "CreationDate": FIXED_PDF_TIMESTAMP,
            "ModDate": FIXED_PDF_TIMESTAMP,
        },
    )
    plt.close(figure)


def main() -> None:
    args = parse_args()
    if args.font:
        font_manager.fontManager.addfont(args.font)
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
