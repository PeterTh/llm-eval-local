import type { DatasetManifest, FilterState, ScoreCubeCell } from "../data/types";
import { summarizeDistribution } from "./statistics";

export type ComplexityDimension = "benchmark" | "backend";

export interface ComplexityCategorySummary {
  categoryType: ComplexityDimension;
  categoryId: string;
  categoryLabel: string;
  categoryKey: string;
  runCount: number;
  meanScore: number;
  firstQuartile: number;
  median: number;
  thirdQuartile: number;
  grandMean: number;
  accessibleDescription: string;
}

export interface ComplexityObservation extends ComplexityCategorySummary {
  score: number;
  observationIndex: number;
}

export interface ComplexityAnalysis {
  benchmarkSummaries: ComplexityCategorySummary[];
  benchmarkObservations: ComplexityObservation[];
  backendSummaries: ComplexityCategorySummary[];
  backendObservations: ComplexityObservation[];
  runCount: number;
  modelCount: number;
  grandMean: number | null;
}

function categoryId(cell: ScoreCubeCell, dimension: ComplexityDimension): string {
  return dimension === "benchmark" ? cell.benchmarkId : cell.backendId;
}

function dimensionLabel(dimension: ComplexityDimension): string {
  return dimension === "benchmark" ? "Benchmark" : "Target";
}

function buildDimension(
  cells: readonly ScoreCubeCell[],
  dimension: ComplexityDimension,
  labels: ReadonlyMap<string, string>,
  grandMean: number,
): { summaries: ComplexityCategorySummary[]; observations: ComplexityObservation[] } {
  const grouped = new Map<string, number[]>();
  for (const cell of cells) {
    const id = categoryId(cell, dimension);
    const scores = grouped.get(id) ?? [];
    for (let index = 0; index < cell.count; index += 1) scores.push(cell.score);
    grouped.set(id, scores);
  }

  const labelCounts = new Map<string, number>();
  for (const id of grouped.keys()) {
    const label = labels.get(id) ?? id;
    labelCounts.set(label, (labelCounts.get(label) ?? 0) + 1);
  }

  const summaries = [...grouped].map(([id, scores]): ComplexityCategorySummary => {
    const statistics = summarizeDistribution(scores);
    const label = labels.get(id) ?? id;
    const categoryKey = labelCounts.get(label) === 1 ? label : `${label} (${id})`;
    const accessibleDescription = `${dimensionLabel(dimension)} ${label}; ${statistics.count} runs; mean ${statistics.mean.toFixed(2)}; median ${statistics.median.toFixed(2)}`;
    return {
      categoryType: dimension,
      categoryId: id,
      categoryLabel: label,
      categoryKey,
      runCount: statistics.count,
      meanScore: statistics.mean,
      firstQuartile: statistics.firstQuartile,
      median: statistics.median,
      thirdQuartile: statistics.thirdQuartile,
      grandMean,
      accessibleDescription,
    };
  }).sort((left, right) =>
    right.meanScore - left.meanScore
    || left.categoryLabel.localeCompare(right.categoryLabel, "en")
    || left.categoryId.localeCompare(right.categoryId, "en"));

  const byId = new Map(summaries.map((summary) => [summary.categoryId, summary]));
  const observations = summaries.flatMap((summary) =>
    (grouped.get(summary.categoryId) ?? []).map((score, observationIndex) => ({
      ...summary,
      score,
      observationIndex,
    })));

  // Keep this assertion local to the derived representation: every group used
  // for observations must also have exactly one computed summary.
  if (byId.size !== grouped.size) throw new Error(`Incomplete ${dimension} complexity summaries`);
  return { summaries, observations };
}

export function analyzeComplexity(
  scoreCube: readonly ScoreCubeCell[],
  manifest: DatasetManifest,
  filters: Pick<FilterState, "models" | "benchmarks" | "backends">,
): ComplexityAnalysis {
  const selectedModels = new Set(filters.models);
  const selectedBenchmarks = new Set(filters.benchmarks);
  const selectedBackends = new Set(filters.backends);
  const cells = scoreCube.filter((cell) =>
    (selectedModels.size === 0 || selectedModels.has(cell.modelId))
    && (selectedBenchmarks.size === 0 || selectedBenchmarks.has(cell.benchmarkId))
    && (selectedBackends.size === 0 || selectedBackends.has(cell.backendId)));

  const scores: number[] = [];
  const models = new Set<string>();
  for (const cell of cells) {
    if (cell.count <= 0) continue;
    models.add(cell.modelId);
    for (let index = 0; index < cell.count; index += 1) scores.push(cell.score);
  }
  if (scores.length === 0) {
    return {
      benchmarkSummaries: [], benchmarkObservations: [],
      backendSummaries: [], backendObservations: [],
      runCount: 0, modelCount: 0, grandMean: null,
    };
  }

  const grandMean = summarizeDistribution(scores).mean;
  const benchmark = buildDimension(
    cells, "benchmark", new Map(manifest.benchmarks.map((entity) => [entity.id, entity.label])), grandMean,
  );
  const backend = buildDimension(
    cells, "backend", new Map(manifest.backends.map((entity) => [entity.id, entity.label])), grandMean,
  );
  return {
    benchmarkSummaries: benchmark.summaries,
    benchmarkObservations: benchmark.observations,
    backendSummaries: backend.summaries,
    backendObservations: backend.observations,
    runCount: scores.length,
    modelCount: models.size,
    grandMean,
  };
}
