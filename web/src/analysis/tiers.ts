import type { DatasetManifest, FilterState, ScoreCubeCell } from "../data/types";

export interface TierSegment {
  modelId: string;
  modelLabel: string;
  bandId: string;
  bandLabel: string;
  bandDetail: string;
  bandOrder: number;
  color: string;
  count: number;
  percentage: number;
  startPercentage: number;
  endPercentage: number;
  midpointPercentage: number;
  runCount: number;
  meanScore: number;
}

export interface TierModelSummary {
  modelId: string;
  modelLabel: string;
  modelHarnessLabel: string;
  modelInvocationLabel: string;
  runCount: number;
  meanScore: number;
  segments: TierSegment[];
}

export function aggregateTiers(
  scoreCube: readonly ScoreCubeCell[],
  manifest: DatasetManifest,
  filters: Pick<FilterState, "models" | "benchmarks" | "backends" | "sort">,
): TierModelSummary[] {
  const selectedModels = new Set(filters.models);
  const selectedBenchmarks = new Set(filters.benchmarks);
  const selectedBackends = new Set(filters.backends);
  const modelLabels = new Map(manifest.models.map((entity) => [entity.id, entity.label]));
  const harnessLabels = new Map(manifest.methodology.harnesses.map((harness) => [harness.id, harness.label]));
  const modelInvocations = new Map(manifest.models.map((model) => [model.id, model.invocation]));
  const accumulators = new Map<string, { runCount: number; scoreTotal: number; bandCounts: Map<string, number> }>();

  for (const cell of scoreCube) {
    if (selectedModels.size > 0 && !selectedModels.has(cell.modelId)) continue;
    if (selectedBenchmarks.size > 0 && !selectedBenchmarks.has(cell.benchmarkId)) continue;
    if (selectedBackends.size > 0 && !selectedBackends.has(cell.backendId)) continue;
    const band = manifest.scoreScale.bands.find((candidate) =>
      cell.score >= candidate.minimum && cell.score <= candidate.maximum);
    if (!band) continue;
    const accumulator = accumulators.get(cell.modelId) ?? {
      runCount: 0,
      scoreTotal: 0,
      bandCounts: new Map<string, number>(),
    };
    accumulator.runCount += cell.count;
    accumulator.scoreTotal += cell.score * cell.count;
    accumulator.bandCounts.set(band.id, (accumulator.bandCounts.get(band.id) ?? 0) + cell.count);
    accumulators.set(cell.modelId, accumulator);
  }

  const summaries = [...accumulators].map(([modelId, accumulator]) => {
    const meanScore = accumulator.scoreTotal / accumulator.runCount;
    const invocation = modelInvocations.get(modelId);
    const modelHarnessLabel = invocation ? (harnessLabels.get(invocation.harnessId) ?? invocation.harnessId) : "Not recorded";
    const modelInvocationLabel = invocation
      ? `${invocation.invokedModelId}${invocation.reasoningEffort ? ` · ${invocation.reasoningEffort} reasoning` : ""}`
      : "Not recorded";
    let cursor = 0;
    const segments = manifest.scoreScale.bands.map((band, bandOrder) => {
      const count = accumulator.bandCounts.get(band.id) ?? 0;
      const percentage = count / accumulator.runCount * 100;
      const startPercentage = cursor;
      cursor += percentage;
      return {
        modelId,
        modelLabel: modelLabels.get(modelId) ?? modelId,
        bandId: band.id,
        bandLabel: band.label,
        bandDetail: band.detail,
        bandOrder,
        color: band.color,
        count,
        percentage,
        startPercentage,
        endPercentage: cursor,
        midpointPercentage: startPercentage + percentage / 2,
        runCount: accumulator.runCount,
        meanScore,
      };
    });
    return {
      modelId,
      modelLabel: modelLabels.get(modelId) ?? modelId,
      modelHarnessLabel,
      modelInvocationLabel,
      runCount: accumulator.runCount,
      meanScore,
      segments,
    };
  });

  summaries.sort((left, right) => {
    if (filters.sort === "alphabetical") return left.modelLabel.localeCompare(right.modelLabel, "en");
    const difference = left.meanScore - right.meanScore;
    return filters.sort === "strongest" ? -difference : difference;
  });
  return summaries;
}
