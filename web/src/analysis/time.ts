import type { DatasetManifest, FilterState, TimeDataset, TimeRunRecord } from "../data/types";
import { summarizeDistribution, type DistributionStatistics } from "./statistics";

export interface TimeModelSummary {
  modelId: string;
  modelLabel: string;
  scoreRunCount: number;
  timeRunCount: number;
  unavailableTimeRunCount: number;
  meanScore: number;
  meanGenerationTimeSeconds: number | null;
  distribution: (DistributionStatistics & { minimum: number; maximum: number }) | null;
  outliers: Array<TimeRunRecord & { generationTimeSeconds: number }>;
}

export interface TimeAnalysis {
  models: TimeModelSummary[];
  plottedModels: TimeModelSummary[];
  scoreRunCount: number;
  timeRunCount: number;
  unavailableTimeRunCount: number;
}

export function analyzeTime(
  dataset: TimeDataset,
  manifest: DatasetManifest,
  filters: Pick<FilterState, "models" | "benchmarks" | "backends">,
): TimeAnalysis {
  const models = new Set(filters.models);
  const benchmarks = new Set(filters.benchmarks);
  const backends = new Set(filters.backends);
  const labels = new Map(manifest.models.map((model) => [model.id, model.label]));
  const groups = new Map<string, TimeRunRecord[]>();
  for (const run of dataset.runs) {
    if (models.size > 0 && !models.has(run.modelId)) continue;
    if (benchmarks.size > 0 && !benchmarks.has(run.benchmarkId)) continue;
    if (backends.size > 0 && !backends.has(run.backendId)) continue;
    const group = groups.get(run.modelId) ?? [];
    group.push(run);
    groups.set(run.modelId, group);
  }
  const summaries = [...groups].map(([modelId, runs]): TimeModelSummary => {
    const timed = runs.filter((run): run is TimeRunRecord & { generationTimeSeconds: number } => run.generationTimeSeconds !== null);
    const times = timed.map((run) => run.generationTimeSeconds);
    const distribution = times.length === 0 ? null : {
      ...summarizeDistribution(times),
      minimum: Math.min(...times),
      maximum: Math.max(...times),
    };
    return {
      modelId,
      modelLabel: labels.get(modelId) ?? modelId,
      scoreRunCount: runs.length,
      timeRunCount: timed.length,
      unavailableTimeRunCount: runs.length - timed.length,
      meanScore: runs.reduce((total, run) => total + run.overallScore, 0) / runs.length,
      meanGenerationTimeSeconds: distribution?.mean ?? null,
      distribution,
      outliers: distribution ? timed.filter((run) =>
        run.generationTimeSeconds < distribution.lowerWhisker || run.generationTimeSeconds > distribution.upperWhisker)
        .sort((left, right) => left.generationTimeSeconds - right.generationTimeSeconds || left.id.localeCompare(right.id, "en")) : [],
    };
  });
  summaries.sort((left, right) => {
    if (left.meanGenerationTimeSeconds === null || right.meanGenerationTimeSeconds === null) {
      if (left.meanGenerationTimeSeconds !== right.meanGenerationTimeSeconds) return left.meanGenerationTimeSeconds === null ? 1 : -1;
    } else if (left.meanGenerationTimeSeconds !== right.meanGenerationTimeSeconds) {
      return right.meanGenerationTimeSeconds - left.meanGenerationTimeSeconds;
    }
    return left.modelLabel.localeCompare(right.modelLabel, "en");
  });
  return {
    models: summaries,
    plottedModels: summaries.filter((model) => model.distribution !== null),
    scoreRunCount: summaries.reduce((total, model) => total + model.scoreRunCount, 0),
    timeRunCount: summaries.reduce((total, model) => total + model.timeRunCount, 0),
    unavailableTimeRunCount: summaries.reduce((total, model) => total + model.unavailableTimeRunCount, 0),
  };
}

/** Domains in seconds; each chart supplies only the observations it displays. */
export function timeDomain(seconds: readonly number[], scale: "linear" | "log"): [number, number] {
  const positive = seconds.filter((value) => Number.isFinite(value) && value > 0);
  if (positive.length === 0) return scale === "linear" ? [0, 60] : [1, 60];
  const minimum = Math.min(...positive);
  const maximum = Math.max(...positive);
  if (scale === "linear") return [0, maximum * 1.08];
  return minimum === maximum ? [minimum / 1.5, maximum * 1.5] : [minimum / 1.2, maximum * 1.2];
}
