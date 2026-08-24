import type { RunRecord } from "../data/types";
import type { CostModelSummary } from "../analysis/cost";

function csvCell(value: unknown): string {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function runsToCsv(runs: readonly RunRecord[]): string {
  const headers = [
    "id", "model", "benchmark", "backend", "repetition", "overall_score",
    "score_band", "validation_status", "benchmark_success", "benchmark_median_ms",
    "source_url", "validation_evidence_url", "benchmark_evidence_url",
  ];
  const rows = runs.map((run) => [
    run.id,
    run.modelId,
    run.benchmarkId,
    run.backendId,
    run.repetition,
    run.overallScore,
    run.scoreBandId,
    run.validationStatus,
    run.benchmarkSuccess,
    run.benchmarkMedianMs,
    run.sourceUrl,
    run.validationEvidenceUrl,
    run.benchmarkEvidenceUrl,
  ].map(csvCell).join(","));
  return `${headers.join(",")}\n${rows.join("\n")}\n`;
}

export function costSummariesToCsv(summaries: readonly CostModelSummary[]): string {
  const headers = [
    "model", "model_label", "score_run_count", "cost_run_count", "unavailable_cost_run_count",
    "mean_score", "estimated_mean_cost_usd", "mean_priced_tokens", "mean_input_tokens",
    "mean_cached_input_tokens", "mean_output_tokens", "effective_observed_price_usd_per_million",
    "pricing_profile", "pricing_as_of", "pricing_model_id", "pricing_provider", "pricing_provider_tag",
    "pricing_quantization", "input_price_usd_per_million", "cached_input_price_usd_per_million",
    "output_price_usd_per_million", "effective_price_usd_per_million", "cost_method",
    "pricing_source_kind", "pricing_selection_policy", "pricing_match_note", "pricing_catalog_url",
    "pricing_endpoint_url", "pricing_source_url", "secondary_pricing_source_url",
  ];
  const rows = summaries.map((summary) => [
    summary.modelId,
    summary.modelLabel,
    summary.scoreRunCount,
    summary.costRunCount,
    summary.unavailableCostRunCount,
    summary.meanScore,
    summary.meanEstimatedCostUsd,
    summary.meanPricedTokens,
    summary.meanInputTokens,
    summary.meanCachedInputTokens,
    summary.meanOutputTokens,
    summary.effectiveObservedPriceUsdPerMillion,
    summary.pricingProfileId,
    summary.pricingAsOf,
    summary.pricingModelId,
    summary.pricingProvider,
    summary.pricingProviderTag,
    summary.pricingQuantization,
    summary.inputPriceUsdPerMillion,
    summary.cachedInputPriceUsdPerMillion,
    summary.outputPriceUsdPerMillion,
    summary.effectivePriceUsdPerMillion,
    summary.costMethod,
    summary.pricingSourceKind,
    summary.pricingSelectionPolicy,
    summary.pricingMatchNote,
    summary.pricingCatalogUrl,
    summary.pricingEndpointUrl,
    summary.pricingSourceUrl,
    summary.secondaryPricingSourceUrl,
  ].map(csvCell).join(","));
  return `${headers.join(",")}\n${rows.join("\n")}\n`;
}

export function downloadText(filename: string, content: string, type: string): void {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}
