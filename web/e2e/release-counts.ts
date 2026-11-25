import { readFileSync, readdirSync } from "node:fs";
import { parse } from "csv-parse/sync";

const catalog = JSON.parse(readFileSync(new URL("../../release/catalog.json", import.meta.url), "utf8"));
const site = JSON.parse(readFileSync(new URL("../config/site.json", import.meta.url), "utf8"));
const excluded = new Set<string>(site.modelSets.find((set: { id: string }) => set.id === site.defaultModelSetId).excludeModelIds);
const runs = parse(readFileSync(new URL("../../release/scored_results.csv", import.meta.url), "utf8"), { columns: true }) as Record<string, string>[];
const defaultRuns = runs.filter((run) => !excluded.has(run.model));

export const allModelCount: number = catalog.expected.models;
export const totalRunCount: number = catalog.expected.runs;
export const defaultModelCount = new Set(defaultRuns.map((run) => run.model)).size;
export const defaultRunCount = defaultRuns.length;

const costFiles = readdirSync(new URL("../public/data/", import.meta.url)).filter((name) => /^cost\.[a-f0-9]+\.json$/.test(name));
if (costFiles.length !== 1) throw new Error("Build website data before browser tests");
const costs = JSON.parse(readFileSync(new URL(`../public/data/${costFiles[0]}`, import.meta.url), "utf8")).runs as { modelId: string; estimatedCostUsd: number | null }[];
export const allCostRunCount = costs.filter((run) => run.estimatedCostUsd != null).length;
export const defaultCostRunCount = costs.filter((run) => !excluded.has(run.modelId) && run.estimatedCostUsd != null).length;

const performanceCell = runs.filter((run) => run.benchmark === site.defaultPerformanceCell.benchmarkId && run.par_type === site.defaultPerformanceCell.backendId);
const successfulCell = performanceCell.filter((run) => run.benchmark_success === "true");
const selectedCell = performanceCell.filter((run) => !excluded.has(run.model));
export const defaultPerformanceSuccessCount = selectedCell.filter((run) => run.benchmark_success === "true").length;
export const defaultPerformanceFailureCount = selectedCell.length - defaultPerformanceSuccessCount;
const fastest = [...successfulCell].sort((left, right) => Number(left.benchmark_median_time) - Number(right.benchmark_median_time))[0]!;
export const performanceBaselineMs = Number(fastest.benchmark_median_time);
export const performanceLeaderLabel: string = site.labels.models[fastest.model];
