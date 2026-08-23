import type { RunRecord } from "../data/types";

export type ValidationOutcome = "all" | "passed" | "failed";
export type BenchmarkOutcome = "all" | "successful" | "failed" | "unavailable";
export type RunSort = "model" | "score-desc" | "score-asc" | "cell";

export interface RunListFilters {
  models: readonly string[];
  scoreBands: readonly string[];
  exactScore: number | null;
  validation: ValidationOutcome;
  benchmark: BenchmarkOutcome;
  query: string;
}

export function filterRuns(runs: readonly RunRecord[], filters: RunListFilters): RunRecord[] {
  const models = new Set(filters.models);
  const bands = new Set(filters.scoreBands);
  const query = filters.query.trim().toLocaleLowerCase();

  return runs.filter((run) => {
    if (models.size > 0 && !models.has(run.modelId)) return false;
    if (bands.size > 0 && !bands.has(run.scoreBandId)) return false;
    if (filters.exactScore !== null && run.overallScore !== filters.exactScore) return false;
    if (filters.validation === "passed" && run.validationStatus !== 5) return false;
    if (filters.validation === "failed" && run.validationStatus === 5) return false;
    if (filters.benchmark === "successful" && run.benchmarkSuccess !== true) return false;
    if (filters.benchmark === "failed" && run.benchmarkSuccess !== false) return false;
    if (filters.benchmark === "unavailable" && run.benchmarkSuccess !== null) return false;
    if (query && ![run.id, run.modelId, run.benchmarkId, run.backendId]
      .some((value) => value.toLocaleLowerCase().includes(query))) return false;
    return true;
  });
}

export function sortRuns(
  runs: readonly RunRecord[],
  sort: RunSort,
  modelLabels: ReadonlyMap<string, string>,
): RunRecord[] {
  return [...runs].sort((left, right) => {
    if (sort === "score-desc" || sort === "score-asc") {
      const scoreDifference = left.overallScore - right.overallScore;
      if (scoreDifference !== 0) return sort === "score-desc" ? -scoreDifference : scoreDifference;
    }
    if (sort === "cell") {
      const cellDifference = `${left.benchmarkId}\0${left.backendId}`
        .localeCompare(`${right.benchmarkId}\0${right.backendId}`, "en");
      if (cellDifference !== 0) return cellDifference;
    }
    const modelDifference = (modelLabels.get(left.modelId) ?? left.modelId)
      .localeCompare(modelLabels.get(right.modelId) ?? right.modelId, "en");
    return modelDifference || left.id.localeCompare(right.id, "en");
  });
}
