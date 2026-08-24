import type {
  CostDataset,
  CostPricingProfile,
  CostRunRecord,
  DatasetManifest,
  FilterState,
} from "../data/types";
import { formatCount, formatScore, formatUsd, formatUsdPerMillion } from "../utils/format";
import { stableStringHash } from "../utils/hash";

const POINT_SHAPES = ["circle", "square", "triangle-up", "diamond", "triangle-down"] as const;

export interface CostModelSummary {
  modelId: string;
  modelLabel: string;
  scoreRunCount: number;
  costRunCount: number;
  unavailableCostRunCount: number;
  meanScore: number;
  meanEstimatedCostUsd: number | null;
  meanPricedTokens: number | null;
  meanInputTokens: number | null;
  meanCachedInputTokens: number | null;
  meanOutputTokens: number | null;
  effectiveObservedPriceUsdPerMillion: number | null;
  pricingProfileId: string | null;
  pricingAsOf: string | null;
  pricingModelId: string | null;
  pricingProvider: string | null;
  pricingProviderTag: string | null;
  pricingQuantization: string | null;
  pricingSourceKind: string | null;
  pricingSelectionPolicy: string | null;
  pricingMatchNote: string | null;
  pricingCatalogUrl: string | null;
  pricingEndpointUrl: string | null;
  pricingSourceUrl: string | null;
  secondaryPricingSourceUrl: string | null;
  inputPriceUsdPerMillion: number | null;
  cachedInputPriceUsdPerMillion: number | null;
  outputPriceUsdPerMillion: number | null;
  effectivePriceUsdPerMillion: number | null;
  costMethod: string;
  pointShape: typeof POINT_SHAPES[number];
  styleIndex: number;
  scoreLabel: string;
  costLabel: string;
  scoreRunCountLabel: string;
  costRunCountLabel: string;
  runCountsLabel: string;
  pricedTokensLabel: string;
  inputTokensLabel: string;
  cachedInputTokensLabel: string;
  outputTokensLabel: string;
  tokenSummaryLabel: string;
  effectiveObservedPriceLabel: string;
  inputPriceLabel: string;
  cachedInputPriceLabel: string;
  outputPriceLabel: string;
  rateSummaryLabel: string;
  providerSummaryLabel: string;
  sourceAvailabilityLabel: string;
  accessibleDescription: string;
}

export interface CostAnalysis {
  models: CostModelSummary[];
  plottedModels: CostModelSummary[];
  scoreRunCount: number;
  costRunCount: number;
  unavailableCostRunCount: number;
  unpricedModelCount: number;
}

function mean(values: readonly number[]): number | null {
  return values.length === 0 ? null : values.reduce((total, value) => total + value, 0) / values.length;
}

function selectedModelIds(manifest: DatasetManifest, selected: readonly string[]): Set<string> {
  return new Set(selected.length > 0 ? selected : manifest.models.map((model) => model.id));
}

export function pricedTokenCountForRun(
  run: CostRunRecord,
  convention: "includes-cached" | "excludes-cached",
): number | null {
  if (run.inputTokens !== null && run.cachedInputTokens !== null && run.outputTokens !== null) {
    return convention === "includes-cached"
      ? run.inputTokens + run.outputTokens
      : run.inputTokens + run.cachedInputTokens + run.outputTokens;
  }
  return run.totalTokens;
}

function profileMethod(
  profile: CostPricingProfile | null,
  convention: "includes-cached" | "excludes-cached",
): string {
  if (!profile) return "Cost unavailable";
  if (profile.effectivePriceUsdPerMillion !== null) {
    return "Combined token count priced with a fixed 50/50 input/output rate";
  }
  return convention === "excludes-cached"
    ? "Uncached input, cached input, and output tokens priced separately"
    : "Input less cached input, cached input, and output tokens priced separately";
}

export function analyzeCost(
  dataset: CostDataset,
  manifest: DatasetManifest,
  filters: Pick<FilterState, "models" | "benchmarks" | "backends">,
): CostAnalysis {
  const models = selectedModelIds(manifest, filters.models);
  const benchmarks = new Set(filters.benchmarks);
  const backends = new Set(filters.backends);
  const grouped = new Map<string, CostRunRecord[]>();
  for (const run of dataset.runs) {
    if (!models.has(run.modelId)) continue;
    if (benchmarks.size > 0 && !benchmarks.has(run.benchmarkId)) continue;
    if (backends.size > 0 && !backends.has(run.backendId)) continue;
    const group = grouped.get(run.modelId) ?? [];
    group.push(run);
    grouped.set(run.modelId, group);
  }

  const modelMetadata = new Map(manifest.models.map((model) => [model.id, model]));
  const profiles = new Map(dataset.profiles.map((profile) => [profile.id, profile]));
  const summaries = [...grouped].map(([modelId, runs]): CostModelSummary => {
    const costable = runs.filter((run): run is CostRunRecord & { estimatedCostUsd: number } => run.estimatedCostUsd !== null);
    const profileIds = new Set(costable.flatMap((run) => run.pricingProfileId === null ? [] : [run.pricingProfileId]));
    const pricingProfileId = profileIds.size === 1 ? [...profileIds][0]! : null;
    const profile = pricingProfileId === null ? null : profiles.get(pricingProfileId) ?? null;
    const convention = dataset.inputTokenAccounting[modelId] ?? "includes-cached";
    const meanScore = mean(runs.map((run) => run.overallScore))!;
    const meanEstimatedCostUsd = mean(costable.map((run) => run.estimatedCostUsd));
    const meanPricedTokens = mean(costable.flatMap((run) => {
      const count = pricedTokenCountForRun(run, convention);
      return count === null ? [] : [count];
    }));
    const meanInputTokens = mean(costable.flatMap((run) => run.inputTokens === null ? [] : [run.inputTokens]));
    const meanCachedInputTokens = mean(costable.flatMap((run) => run.cachedInputTokens === null ? [] : [run.cachedInputTokens]));
    const meanOutputTokens = mean(costable.flatMap((run) => run.outputTokens === null ? [] : [run.outputTokens]));
    const effectiveObservedPriceUsdPerMillion = meanEstimatedCostUsd !== null && meanPricedTokens !== null && meanPricedTokens > 0
      ? meanEstimatedCostUsd / meanPricedTokens * 1_000_000
      : null;
    const modelLabel = modelMetadata.get(modelId)?.label ?? modelId;
    const hash = stableStringHash(modelId);
    const costMethod = profileMethod(profile, convention);
    const runCountsLabel = `${formatCount(runs.length)} scored · ${formatCount(costable.length)} costed`;
    const tokenSummaryLabel = [
      `${formatCount(meanInputTokens)} input`,
      `${formatCount(meanCachedInputTokens)} cached`,
      `${formatCount(meanOutputTokens)} output`,
      `${formatCount(meanPricedTokens)} priced`,
    ].join(" · ");
    const rateSummaryLabel = [
      `${formatUsd(profile?.inputPriceUsdPerMillion ?? null)} input`,
      `${formatUsd(profile?.cachedInputPriceUsdPerMillion ?? null)} cached`,
      `${formatUsd(profile?.outputPriceUsdPerMillion ?? null)} output`,
      `${formatUsd(effectiveObservedPriceUsdPerMillion)} observed`,
    ].join(" · ");
    const providerSummaryLabel = profile
      ? `${profile.pricingProvider} · ${profile.pricingProviderTag}`
      : "—";
    const sourceAvailabilityLabel = profile
      ? [
          "Pricing source",
          profile.pricingEndpointUrl ? "endpoint record" : null,
          profile.secondaryPricingSourceUrl ? "secondary source" : null,
        ].filter(Boolean).join(", ")
      : "No pricing source";
    return {
      modelId,
      modelLabel,
      scoreRunCount: runs.length,
      costRunCount: costable.length,
      unavailableCostRunCount: runs.length - costable.length,
      meanScore,
      meanEstimatedCostUsd,
      meanPricedTokens,
      meanInputTokens,
      meanCachedInputTokens,
      meanOutputTokens,
      effectiveObservedPriceUsdPerMillion,
      pricingProfileId,
      pricingAsOf: profile?.pricingAsOf ?? null,
      pricingModelId: profile?.pricingModelId ?? null,
      pricingProvider: profile?.pricingProvider ?? null,
      pricingProviderTag: profile?.pricingProviderTag ?? null,
      pricingQuantization: profile?.pricingQuantization ?? null,
      pricingSourceKind: profile?.pricingSourceKind ?? null,
      pricingSelectionPolicy: profile?.pricingSelectionPolicy ?? null,
      pricingMatchNote: profile?.pricingMatchNote ?? null,
      pricingCatalogUrl: profile?.pricingCatalogUrl ?? null,
      pricingEndpointUrl: profile?.pricingEndpointUrl ?? null,
      pricingSourceUrl: profile?.pricingSourceUrl ?? null,
      secondaryPricingSourceUrl: profile?.secondaryPricingSourceUrl ?? null,
      inputPriceUsdPerMillion: profile?.inputPriceUsdPerMillion ?? null,
      cachedInputPriceUsdPerMillion: profile?.cachedInputPriceUsdPerMillion ?? null,
      outputPriceUsdPerMillion: profile?.outputPriceUsdPerMillion ?? null,
      effectivePriceUsdPerMillion: profile?.effectivePriceUsdPerMillion ?? null,
      costMethod,
      pointShape: POINT_SHAPES[hash % POINT_SHAPES.length]!,
      styleIndex: hash % 7,
      scoreLabel: formatScore(meanScore),
      costLabel: formatUsd(meanEstimatedCostUsd),
      scoreRunCountLabel: formatCount(runs.length),
      costRunCountLabel: formatCount(costable.length),
      runCountsLabel,
      pricedTokensLabel: formatCount(meanPricedTokens),
      inputTokensLabel: formatCount(meanInputTokens),
      cachedInputTokensLabel: formatCount(meanCachedInputTokens),
      outputTokensLabel: formatCount(meanOutputTokens),
      tokenSummaryLabel,
      effectiveObservedPriceLabel: formatUsdPerMillion(effectiveObservedPriceUsdPerMillion),
      inputPriceLabel: formatUsdPerMillion(profile?.inputPriceUsdPerMillion ?? null),
      cachedInputPriceLabel: formatUsdPerMillion(profile?.cachedInputPriceUsdPerMillion ?? null),
      outputPriceLabel: formatUsdPerMillion(profile?.outputPriceUsdPerMillion ?? null),
      rateSummaryLabel,
      providerSummaryLabel,
      sourceAvailabilityLabel,
      accessibleDescription: `${modelLabel}; mean score ${formatScore(meanScore)} from ${formatCount(runs.length)} runs; estimated mean cost ${formatUsd(meanEstimatedCostUsd)} from ${formatCount(costable.length)} runs`,
    };
  });
  summaries.sort((left, right) => {
    if (left.meanEstimatedCostUsd === null || right.meanEstimatedCostUsd === null) {
      if (left.meanEstimatedCostUsd === null && right.meanEstimatedCostUsd === null) {
        return left.modelLabel.localeCompare(right.modelLabel, "en");
      }
      return left.meanEstimatedCostUsd === null ? 1 : -1;
    }
    return left.meanEstimatedCostUsd - right.meanEstimatedCostUsd
      || left.modelLabel.localeCompare(right.modelLabel, "en");
  });
  const plottedModels = summaries.filter((model): model is CostModelSummary & { meanEstimatedCostUsd: number } =>
    model.meanEstimatedCostUsd !== null && model.meanEstimatedCostUsd > 0);
  return {
    models: summaries,
    plottedModels,
    scoreRunCount: summaries.reduce((total, model) => total + model.scoreRunCount, 0),
    costRunCount: summaries.reduce((total, model) => total + model.costRunCount, 0),
    unavailableCostRunCount: summaries.reduce((total, model) => total + model.unavailableCostRunCount, 0),
    unpricedModelCount: summaries.filter((model) => model.meanEstimatedCostUsd === null).length,
  };
}

export function adaptiveScoreDomain(
  values: readonly number[],
  minimum: number,
  maximum: number,
): [number, number] {
  if (values.length === 0) return [minimum, maximum];
  const observedMinimum = Math.min(...values);
  const observedMaximum = Math.max(...values);
  if (observedMinimum === observedMaximum) {
    return [Math.max(minimum, observedMinimum - 0.5), Math.min(maximum, observedMaximum + 0.5)];
  }
  const padding = Math.max(0.25, (observedMaximum - observedMinimum) * 0.08);
  return [Math.max(minimum, observedMinimum - padding), Math.min(maximum, observedMaximum + padding)];
}

export function costDomain(values: readonly number[], scale: "log" | "linear"): [number, number] {
  const positive = values.filter((value) => value > 0);
  if (positive.length === 0) return scale === "log" ? [0.01, 1] : [0, 1];
  const minimum = Math.min(...positive);
  const maximum = Math.max(...positive);
  if (scale === "linear") return [0, maximum * 1.08];
  return minimum === maximum ? [minimum / 1.5, maximum * 1.5] : [minimum / 1.2, maximum * 1.2];
}
