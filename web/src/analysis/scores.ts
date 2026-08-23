import type { DatasetManifest, FilterState, RunRecord } from "../data/types";

export interface ScoreDistributionPoint {
  runId: string;
  modelId: string;
  modelLabel: string;
  benchmarkId: string;
  benchmarkLabel: string;
  backendId: string;
  backendLabel: string;
  repetition: number;
  score: number;
  scoreBandId: string;
  scoreBandLabel: string;
  scoreBandDetail: string;
  jitter: number;
  isOutlier: boolean;
  runCount: number;
  meanScore: number;
  lowerWhisker: number;
  firstQuartile: number;
  median: number;
  thirdQuartile: number;
  upperWhisker: number;
  outlierCount: number;
}

export interface ModelScoreSummary {
  modelId: string;
  modelLabel: string;
  modelHarnessLabel: string;
  modelInvocationLabel: string;
  runCount: number;
  meanScore: number;
  lowerWhisker: number;
  firstQuartile: number;
  median: number;
  thirdQuartile: number;
  upperWhisker: number;
  outlierCount: number;
  points: ScoreDistributionPoint[];
}

function quantileSorted(values: readonly number[], probability: number): number {
  if (values.length === 1) return values[0]!;
  const index = (values.length - 1) * probability;
  const lowerIndex = Math.floor(index);
  const upperIndex = Math.ceil(index);
  const lower = values[lowerIndex]!;
  const upper = values[upperIndex]!;
  return lower + (upper - lower) * (index - lowerIndex);
}

export function deterministicJitter(id: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < id.length; index += 1) {
    hash ^= id.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return 0.1 + (hash >>> 0) / 0xffff_ffff * 0.8;
}

export function summarizeModelScores(
  runs: readonly RunRecord[],
  manifest: DatasetManifest,
  filters: Pick<FilterState, "models" | "benchmarks" | "backends" | "sort">,
): ModelScoreSummary[] {
  const selectedModels = new Set(filters.models);
  const selectedBenchmarks = new Set(filters.benchmarks);
  const selectedBackends = new Set(filters.backends);
  const grouped = new Map<string, RunRecord[]>();

  for (const run of runs) {
    if (selectedModels.size > 0 && !selectedModels.has(run.modelId)) continue;
    if (selectedBenchmarks.size > 0 && !selectedBenchmarks.has(run.benchmarkId)) continue;
    if (selectedBackends.size > 0 && !selectedBackends.has(run.backendId)) continue;
    const modelRuns = grouped.get(run.modelId) ?? [];
    modelRuns.push(run);
    grouped.set(run.modelId, modelRuns);
  }

  const models = new Map(manifest.models.map((model) => [model.id, model]));
  const harnessLabels = new Map(manifest.methodology.harnesses.map((harness) => [harness.id, harness.label]));
  const benchmarkLabels = new Map(manifest.benchmarks.map((benchmark) => [benchmark.id, benchmark.label]));
  const backendLabels = new Map(manifest.backends.map((backend) => [backend.id, backend.label]));
  const scoreBands = new Map(manifest.scoreScale.bands.map((band) => [band.id, band]));

  const summaries = [...grouped].map(([modelId, modelRuns]) => {
    const scores = modelRuns.map((run) => run.overallScore).sort((left, right) => left - right);
    const firstQuartile = quantileSorted(scores, 0.25);
    const median = quantileSorted(scores, 0.5);
    const thirdQuartile = quantileSorted(scores, 0.75);
    const interquartileRange = thirdQuartile - firstQuartile;
    const lowerFence = firstQuartile - 1.5 * interquartileRange;
    const upperFence = thirdQuartile + 1.5 * interquartileRange;
    const lowerWhisker = scores.find((score) => score >= lowerFence) ?? scores[0]!;
    const upperWhisker = [...scores].reverse().find((score) => score <= upperFence) ?? scores.at(-1)!;
    const meanScore = scores.reduce((total, score) => total + score, 0) / scores.length;
    const model = models.get(modelId);
    const invocation = model?.invocation;
    const modelLabel = model?.label ?? modelId;
    const modelHarnessLabel = invocation ? (harnessLabels.get(invocation.harnessId) ?? invocation.harnessId) : "Not recorded";
    const modelInvocationLabel = invocation
      ? `${invocation.invokedModelId}${invocation.reasoningEffort ? ` · ${invocation.reasoningEffort} reasoning` : ""}`
      : "Not recorded";
    const outlierCount = scores.filter((score) => score < lowerWhisker || score > upperWhisker).length;

    const points = modelRuns
      .map((run): ScoreDistributionPoint => {
        const band = scoreBands.get(run.scoreBandId)
          ?? manifest.scoreScale.bands.find((candidate) => run.overallScore >= candidate.minimum && run.overallScore <= candidate.maximum);
        return {
          runId: run.id,
          modelId,
          modelLabel,
          benchmarkId: run.benchmarkId,
          benchmarkLabel: benchmarkLabels.get(run.benchmarkId) ?? run.benchmarkId,
          backendId: run.backendId,
          backendLabel: backendLabels.get(run.backendId) ?? run.backendId,
          repetition: run.repetition,
          score: run.overallScore,
          scoreBandId: band?.id ?? run.scoreBandId,
          scoreBandLabel: band?.label ?? run.scoreBandId,
          scoreBandDetail: band?.detail ?? "Unrecognized score band",
          jitter: deterministicJitter(run.id),
          isOutlier: run.overallScore < lowerWhisker || run.overallScore > upperWhisker,
          runCount: scores.length,
          meanScore,
          lowerWhisker,
          firstQuartile,
          median,
          thirdQuartile,
          upperWhisker,
          outlierCount,
        };
      })
      .sort((left, right) => left.score - right.score || left.runId.localeCompare(right.runId, "en"));

    return {
      modelId,
      modelLabel,
      modelHarnessLabel,
      modelInvocationLabel,
      runCount: scores.length,
      meanScore,
      lowerWhisker,
      firstQuartile,
      median,
      thirdQuartile,
      upperWhisker,
      outlierCount,
      points,
    };
  });

  summaries.sort((left, right) => {
    if (filters.sort === "alphabetical") return left.modelLabel.localeCompare(right.modelLabel, "en");
    const difference = left.meanScore - right.meanScore;
    if (difference !== 0) return filters.sort === "strongest" ? -difference : difference;
    return left.modelLabel.localeCompare(right.modelLabel, "en");
  });
  return summaries;
}
