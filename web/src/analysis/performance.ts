import type {
  CellDescriptor,
  DatasetManifest,
  FilterState,
  RunRecord,
} from "../data/types";
import { formatMilliseconds } from "../utils/format";
import { summarizeDistribution } from "./statistics";

export type PerformanceOrder = "fastest" | "slowest" | "alphabetical";

export interface PerformancePoint {
  runId: string;
  modelId: string;
  modelLabel: string;
  repetition: number;
  medianMs: number;
  medianLabel: string;
  relativeToFastest: number;
  measurementMinimumMs: number;
  measurementMaximumMs: number;
  plotValue: number;
  plotMinimum: number;
  plotMaximum: number;
  measurementsLabel: string;
  sourceAvailabilityLabel: string;
  accessibleDescription: string;
}

export interface ModelPerformanceSummary {
  modelId: string;
  modelLabel: string;
  modelHarnessLabel: string;
  modelInvocationLabel: string;
  attemptedRunCount: number;
  successfulRunCount: number;
  benchmarkFailureCount: number;
  notBenchmarkedCount: number;
  omittedRunCount: number;
  medianMs: number | null;
  relativeMedian: number | null;
  plotMedian: number | null;
  zeroSuccessLabel: string;
  points: PerformancePoint[];
}

export interface PerformanceAnalysis {
  models: ModelPerformanceSummary[];
  fullCellFastestMs: number | null;
  attemptedRunCount: number;
  successfulRunCount: number;
  benchmarkFailureCount: number;
  notBenchmarkedCount: number;
  omittedRunCount: number;
}

function selectedModelIds(manifest: DatasetManifest, selected: readonly string[]): string[] {
  if (selected.length === 0) return manifest.models.map((model) => model.id);
  const requested = new Set(selected);
  return manifest.models.filter((model) => requested.has(model.id)).map((model) => model.id);
}

export function resolvePerformanceCell(
  manifest: DatasetManifest,
  selectedBenchmarks: readonly string[],
  selectedBackends: readonly string[],
): CellDescriptor | null {
  const requestedBenchmarks = new Set(selectedBenchmarks);
  const requestedBackends = new Set(selectedBackends);
  const requestedCell = manifest.cells.find((cell) =>
    (requestedBenchmarks.size === 0 || requestedBenchmarks.has(cell.benchmarkId))
    && (requestedBackends.size === 0 || requestedBackends.has(cell.backendId)));
  if (requestedBenchmarks.size > 0 || requestedBackends.size > 0) {
    return requestedCell ?? null;
  }
  const configured = manifest.defaultPerformanceCell;
  return (configured
    ? manifest.cells.find((cell) =>
        cell.benchmarkId === configured.benchmarkId && cell.backendId === configured.backendId)
    : undefined)
    ?? manifest.cells.find((cell) => cell.successfulRunCount > 0)
    ?? manifest.cells[0]
    ?? null;
}

export function analyzePerformance(
  cellRuns: readonly RunRecord[],
  manifest: DatasetManifest,
  filters: Pick<FilterState, "models" | "performanceMode">,
  order: PerformanceOrder,
): PerformanceAnalysis {
  const fullCellSuccessfulRuns = cellRuns.filter((run) =>
    run.benchmarkSuccess === true && run.benchmarkMedianMs !== null);
  const fullCellFastestMs = fullCellSuccessfulRuns.length > 0
    ? Math.min(...fullCellSuccessfulRuns.map((run) => run.benchmarkMedianMs!))
    : null;
  const runsByModel = new Map<string, RunRecord[]>();
  for (const run of cellRuns) {
    const modelRuns = runsByModel.get(run.modelId) ?? [];
    modelRuns.push(run);
    runsByModel.set(run.modelId, modelRuns);
  }

  const models = new Map(manifest.models.map((model) => [model.id, model]));
  const harnessLabels = new Map(manifest.methodology.harnesses.map((harness) => [harness.id, harness.label]));
  const summaries = selectedModelIds(manifest, filters.models).map((modelId): ModelPerformanceSummary => {
    const modelRuns = runsByModel.get(modelId) ?? [];
    const successfulRuns = modelRuns.filter((run) =>
      run.benchmarkSuccess === true && run.benchmarkMedianMs !== null);
    const benchmarkFailureCount = modelRuns.filter((run) => run.benchmarkSuccess === false).length;
    const notBenchmarkedCount = modelRuns.filter((run) => run.benchmarkSuccess === null).length;
    const medianMs = successfulRuns.length > 0
      ? summarizeDistribution(successfulRuns.map((run) => run.benchmarkMedianMs!)).median
      : null;
    const relativeMedian = medianMs !== null && fullCellFastestMs !== null
      ? medianMs / fullCellFastestMs
      : null;
    const model = models.get(modelId);
    const invocation = model?.invocation;
    const modelLabel = model?.label ?? modelId;
    const modelHarnessLabel = invocation
      ? (harnessLabels.get(invocation.harnessId) ?? invocation.harnessId)
      : "Not recorded";
    const modelInvocationLabel = invocation
      ? `${invocation.invokedModelId}${invocation.reasoningEffort ? ` · ${invocation.reasoningEffort} reasoning` : ""}`
      : "Not recorded";
    const points = successfulRuns.map((run): PerformancePoint => {
      const median = run.benchmarkMedianMs!;
      const measurements = run.benchmarkMeasurementsMs.length > 0
        ? run.benchmarkMeasurementsMs
        : [median];
      const measurementMinimumMs = Math.min(...measurements);
      const measurementMaximumMs = Math.max(...measurements);
      const relativeToFastest = fullCellFastestMs === null ? 1 : median / fullCellFastestMs;
      const relativeMinimum = fullCellFastestMs === null ? 1 : measurementMinimumMs / fullCellFastestMs;
      const relativeMaximum = fullCellFastestMs === null ? 1 : measurementMaximumMs / fullCellFastestMs;
      const plotValue = filters.performanceMode === "relative" ? relativeToFastest : median;
      const plotMinimum = filters.performanceMode === "relative" ? relativeMinimum : measurementMinimumMs;
      const plotMaximum = filters.performanceMode === "relative" ? relativeMaximum : measurementMaximumMs;
      return {
        runId: run.id,
        modelId,
        modelLabel,
        repetition: run.repetition,
        medianMs: median,
        medianLabel: formatMilliseconds(median),
        relativeToFastest,
        measurementMinimumMs,
        measurementMaximumMs,
        plotValue,
        plotMinimum,
        plotMaximum,
        measurementsLabel: measurements.map((measurement) => formatMilliseconds(measurement)).join(", "),
        sourceAvailabilityLabel: run.benchmarkEvidenceUrl === null
          ? "Generated source and validation evidence"
          : "Generated source, validation, and benchmark evidence",
        accessibleDescription: `Run ${run.id}; ${modelLabel}; repetition ${run.repetition}; median ${formatMilliseconds(median)}; ${relativeToFastest.toFixed(2)} times the full-cell fastest run`,
      };
    }).sort((left, right) => left.medianMs - right.medianMs || left.runId.localeCompare(right.runId, "en"));
    const omittedRunCount = modelRuns.length - successfulRuns.length;
    return {
      modelId,
      modelLabel,
      modelHarnessLabel,
      modelInvocationLabel,
      attemptedRunCount: modelRuns.length,
      successfulRunCount: successfulRuns.length,
      benchmarkFailureCount,
      notBenchmarkedCount,
      omittedRunCount,
      medianMs,
      relativeMedian,
      plotMedian: filters.performanceMode === "relative" ? relativeMedian : medianMs,
      zeroSuccessLabel: successfulRuns.length > 0
        ? ""
        : modelRuns.length > 0
          ? `0/${modelRuns.length} successful`
          : "No observations",
      points,
    };
  });

  summaries.sort((left, right) => {
    if (order === "alphabetical") {
      return left.modelLabel.localeCompare(right.modelLabel, "en")
        || left.modelId.localeCompare(right.modelId, "en");
    }
    if (left.medianMs === null || right.medianMs === null) {
      if (left.medianMs === null && right.medianMs === null) {
        return left.modelLabel.localeCompare(right.modelLabel, "en")
          || left.modelId.localeCompare(right.modelId, "en");
      }
      return left.medianMs === null ? 1 : -1;
    }
    const difference = left.medianMs - right.medianMs;
    if (difference !== 0) return order === "slowest" ? -difference : difference;
    return left.modelLabel.localeCompare(right.modelLabel, "en")
      || left.modelId.localeCompare(right.modelId, "en");
  });

  return {
    models: summaries,
    fullCellFastestMs,
    attemptedRunCount: summaries.reduce((total, model) => total + model.attemptedRunCount, 0),
    successfulRunCount: summaries.reduce((total, model) => total + model.successfulRunCount, 0),
    benchmarkFailureCount: summaries.reduce((total, model) => total + model.benchmarkFailureCount, 0),
    notBenchmarkedCount: summaries.reduce((total, model) => total + model.notBenchmarkedCount, 0),
    omittedRunCount: summaries.reduce((total, model) => total + model.omittedRunCount, 0),
  };
}
