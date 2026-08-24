import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile, readdir, rm, mkdir, writeFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { parse as parseCsv } from "csv-parse/sync";
import { parse as parseYaml } from "yaml";

import type {
  CellDescriptor,
  CostDataset,
  DatasetManifest,
  EntityMetadata,
  HarnessMetadata,
  MethodologyMetadata,
  ModelMetadata,
  ModelSetMetadata,
  RunRecord,
  RunIndexEntry,
  ScoreBand,
  ScoreCubeCell,
} from "../src/data/types";
import {
  costRunFromScoredRow,
  parseCostPricingProfiles,
  reconcileCanonicalCostAggregates,
  validateCostConfig,
} from "./cost-data";

interface SiteConfig {
  title: string;
  subtitle: string;
  scoreScale: {
    minimum: number;
    maximum: number;
    bands: ScoreBand[];
  };
  labels?: Record<string, Record<string, string>>;
  orders?: Record<string, string[]>;
  modelSets?: Array<{
    id: string;
    label: string;
    excludeModelIds: string[];
  }>;
  defaultModelSetId?: string;
  defaultPerformanceCell?: {
    benchmarkId: string;
    backendId: string;
  };
}

interface MethodologyConfig {
  experimentScript: {
    repository: string;
    commit: string;
    path: string;
    sha256: string;
  };
  harnesses: HarnessMetadata[];
  models: Record<string, {
    harnessId: string;
    invokedModelId: string;
    reasoningEffort?: string;
  }>;
}

interface ValidationRecord {
  id: string;
  benchmark: string;
  model: string;
  backend: string;
  repetition: number;
  source: {
    batch: string;
    path: string;
  };
  stages: Record<string, boolean | null>;
}

interface BenchmarkRecord {
  id: string;
  benchmark: string;
  model: string;
  backend: string;
  repetition: number;
  success: boolean;
  metrics: Array<Record<string, unknown>>;
}

interface LocatedRecord<T> {
  record: T;
  relativePath: string;
  line: number;
}

type CsvRow = Record<string, string>;

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(scriptDirectory, "..");
const repositoryRoot = resolve(webRoot, "..");
const publicDataRoot = resolve(webRoot, "public", "data");
const generatedSourceRoot = resolve(webRoot, "src", "generated");

function invariant(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function requiredRecord(value: unknown, field: string): Record<string, unknown> {
  invariant(typeof value === "object" && value !== null && !Array.isArray(value), `${field} must be an object`);
  return value as Record<string, unknown>;
}

function requiredString(value: unknown, field: string): string {
  invariant(typeof value === "string" && value.trim() !== "", `${field} must be a non-empty string`);
  return value;
}

function lscpuValue(lscpu: string, field: string): string {
  const match = lscpu.split(/\r?\n/).map((line) => line.match(/^([^:]+):\s*(.+)$/))
    .find((candidate) => candidate?.[1]?.trim() === field);
  invariant(match?.[2], `lscpu field is missing: ${field}`);
  return match[2].trim();
}

function lscpuInteger(lscpu: string, field: string): number {
  const value = Number(lscpuValue(lscpu, field));
  invariant(Number.isInteger(value) && value > 0, `lscpu field is not a positive integer: ${field}`);
  return value;
}

function executionSystemFrom(evaluationManifest: Record<string, unknown>): MethodologyMetadata["executionSystem"] {
  const environment = requiredRecord(evaluationManifest.environment, "evaluation manifest environment");
  const lscpu = requiredString(environment.lscpu, "environment.lscpu");
  const sockets = lscpuInteger(lscpu, "Socket(s)");
  const coresPerSocket = lscpuInteger(lscpu, "Core(s) per socket");
  const gpuLines = requiredString(environment.gpus, "environment.gpus").split(/\r?\n/).filter(Boolean);
  const gpus = gpuLines.map((line, lineIndex) => {
    const parts = line.split(",").map((part) => part.trim());
    invariant(parts.length >= 3, `malformed GPU inventory line ${lineIndex + 1}`);
    const index = Number(parts[0]);
    const memoryMatch = parts[2]?.match(/^(\d+)\s+MiB$/);
    invariant(Number.isInteger(index) && index >= 0, `malformed GPU index on line ${lineIndex + 1}`);
    invariant(memoryMatch, `malformed GPU memory on line ${lineIndex + 1}`);
    return { index, model: parts[1]!, memoryMiB: Number(memoryMatch[1]) };
  });

  const resourceProfileRoot = requiredRecord(evaluationManifest.resource_profiles, "evaluation manifest resource_profiles");
  const resourceProfiles = ["validation", "benchmark"].flatMap((phase) => {
    const profiles = requiredRecord(resourceProfileRoot[phase], `resource_profiles.${phase}`);
    return Object.entries(profiles).map(([backendId, description]) => ({
      phase,
      backendId,
      description: requiredString(description, `resource_profiles.${phase}.${backendId}`),
    }));
  });

  return {
    hostname: requiredString(environment.hostname, "environment.hostname"),
    cpu: {
      model: lscpuValue(lscpu, "Model name"),
      physicalCores: coresPerSocket * sockets,
      sockets,
      numaNodes: lscpuInteger(lscpu, "NUMA node(s)"),
    },
    gpus,
    toolchain: {
      ruby: requiredString(environment.ruby, "environment.ruby"),
      cmake: requiredString(environment.cmake, "environment.cmake"),
      c: requiredString(environment.cc, "environment.cc"),
      cxx: requiredString(environment.cxx, "environment.cxx"),
      cuda: requiredString(environment.nvcc, "environment.nvcc"),
      mpi: requiredString(environment.mpi, "environment.mpi"),
    },
    resourceProfiles,
  };
}

function json(value: unknown): string {
  return `${JSON.stringify(value)}\n`;
}

function digest(content: string): string {
  return createHash("sha256").update(content).digest("hex");
}

function toPosixPath(path: string): string {
  return path.split(sep).join("/");
}

function githubRepositoryUrl(remote: string): string {
  const trimmed = remote.trim().replace(/\.git$/, "");
  const sshMatch = trimmed.match(/^git@github\.com:(.+)$/);
  if (sshMatch) {
    return `https://github.com/${sshMatch[1]}`;
  }
  invariant(trimmed.startsWith("https://github.com/"), `unsupported GitHub remote: ${remote}`);
  return trimmed;
}

function encodeRepositoryPath(path: string): string {
  return path.split(/[\\/]/).filter(Boolean).map(encodeURIComponent).join("/");
}

function parseRequiredInteger(value: string | undefined, field: string): number {
  invariant(value !== undefined && value.trim() !== "", `missing ${field}`);
  const parsed = Number(value);
  invariant(Number.isInteger(parsed), `${field} must be an integer: ${value}`);
  return parsed;
}

function parseOptionalNumber(value: string | undefined, field: string): number | null {
  if (value === undefined || value.trim() === "") {
    return null;
  }
  const parsed = Number(value);
  invariant(Number.isFinite(parsed), `${field} must be finite: ${value}`);
  return parsed;
}

function parseOptionalBoolean(value: string | undefined, field: string): boolean | null {
  if (value === undefined || value.trim() === "") {
    return null;
  }
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`${field} must be true, false, or empty: ${value}`);
}

function orderedEntities(
  kind: "models" | "benchmarks" | "backends",
  identifiers: Iterable<string>,
  config: SiteConfig,
): EntityMetadata[] {
  const labels = config.labels?.[kind] ?? {};
  const preferredOrder = config.orders?.[kind] ?? [];
  const orderIndex = new Map(preferredOrder.map((identifier, index) => [identifier, index]));
  return [...new Set(identifiers)]
    .map((id) => ({ id, label: labels[id] ?? id }))
    .sort((left, right) => {
      const leftOrder = orderIndex.get(left.id);
      const rightOrder = orderIndex.get(right.id);
      if (leftOrder !== undefined || rightOrder !== undefined) {
        return (leftOrder ?? Number.MAX_SAFE_INTEGER) - (rightOrder ?? Number.MAX_SAFE_INTEGER);
      }
      return left.label.localeCompare(right.label, "en");
    });
}

async function filesUnder(root: string, suffix: string): Promise<string[]> {
  const entries = await readdir(root, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const path = resolve(root, entry.name);
    if (entry.isDirectory()) return filesUnder(path, suffix);
    return entry.isFile() && entry.name.endsWith(suffix) ? [path] : [];
  }));
  return nested.flat().sort((left, right) => left.localeCompare(right, "en"));
}

async function readJsonlRecords<T>(root: string): Promise<Map<string, LocatedRecord<T>>> {
  const records = new Map<string, LocatedRecord<T>>();
  for (const path of await filesUnder(root, ".jsonl")) {
    const lines = (await readFile(path, "utf8")).split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      if (!line) continue;
      const record = JSON.parse(line) as T & { id?: unknown };
      invariant(typeof record.id === "string" && record.id !== "", `missing record ID at ${path}:${index + 1}`);
      invariant(!records.has(record.id), `duplicate record ID: ${record.id}`);
      records.set(record.id, {
        record,
        relativePath: toPosixPath(relative(repositoryRoot, path)),
        line: index + 1,
      });
    }
  }
  return records;
}

function recordId(row: CsvRow): string {
  const benchmark = row.benchmark;
  const model = row.model;
  const backend = row.par_type;
  const repetition = row.run;
  invariant(benchmark && model && backend && repetition, "scored row is missing its identity fields");
  return `${benchmark}_${model}_${backend}_r${repetition}`;
}

function bandFor(score: number, bands: ScoreBand[]): ScoreBand {
  const matches = bands.filter((band) => score >= band.minimum && score <= band.maximum);
  invariant(matches.length === 1, `score ${score} belongs to ${matches.length} score bands`);
  return matches[0]!;
}

async function writeHashedAsset(prefix: string, value: unknown): Promise<string> {
  const content = json(value);
  const filename = `${prefix}.${digest(content).slice(0, 16)}.json`;
  await writeFile(resolve(publicDataRoot, filename), content, "utf8");
  return `data/${filename}`;
}

export async function buildData(): Promise<void> {
  const config = JSON.parse(await readFile(resolve(webRoot, "config", "site.json"), "utf8")) as SiteConfig;
  const methodologyConfig = JSON.parse(await readFile(resolve(webRoot, "config", "methodology.json"), "utf8")) as MethodologyConfig;
  const costConfig = JSON.parse(await readFile(resolve(webRoot, "config", "cost.json"), "utf8")) as unknown;
  invariant(config.scoreScale.bands.length > 0, "at least one score band is required");

  const harnessIds = new Set<string>();
  for (const harness of methodologyConfig.harnesses) {
    invariant(harness.id && harness.label && harness.commandTemplate, "harness metadata is incomplete");
    invariant(!harnessIds.has(harness.id), `duplicate harness ID: ${harness.id}`);
    invariant(Array.isArray(harness.parameters) && harness.parameters.every((parameter) => parameter.trim() !== ""),
      `harness parameters are malformed: ${harness.id}`);
    harnessIds.add(harness.id);
  }
  invariant(/^[0-9a-f]{40}$/.test(methodologyConfig.experimentScript.commit), "experiment script commit is malformed");
  invariant(/^[0-9a-f]{64}$/.test(methodologyConfig.experimentScript.sha256), "experiment script digest is malformed");
  invariant(methodologyConfig.experimentScript.repository.startsWith("https://github.com/"), "experiment repository must be on GitHub");

  const scoredRows = parseCsv(await readFile(resolve(repositoryRoot, "data", "scoring", "scored_results.csv"), "utf8"), {
    columns: true,
    skip_empty_lines: true,
  }) as CsvRow[];
  const costSourcePath = "analysis/tables/4d_all_models_score_vs_cost.csv";
  const costSourceContent = await readFile(resolve(repositoryRoot, ...costSourcePath.split("/")), "utf8");
  const costSourceDigest = digest(costSourceContent);
  const costSourceRows = parseCsv(costSourceContent, {
    columns: true,
    skip_empty_lines: true,
  }) as CsvRow[];
  const parsedCostProfiles = parseCostPricingProfiles(costSourceRows);
  const thresholdRows = parseCsv(await readFile(resolve(repositoryRoot, "data", "scoring", "local_scoring_thresholds.csv"), "utf8"), {
    columns: true,
    skip_empty_lines: true,
  }) as CsvRow[];
  const scoringMetadata = parseYaml(await readFile(resolve(repositoryRoot, "data", "scoring", "scoring_metadata.yaml"), "utf8")) as Record<string, unknown>;
  const repositoryMetadata = parseYaml(await readFile(resolve(repositoryRoot, "data", "provenance", "repositories.yaml"), "utf8")) as Record<string, any>;
  const evaluationManifest = parseYaml(await readFile(resolve(repositoryRoot, "data", "provenance", "evaluation_manifest.yaml"), "utf8")) as Record<string, unknown>;

  const validationRecords = await readJsonlRecords<ValidationRecord>(resolve(repositoryRoot, "data", "validation", "records"));
  const benchmarkRecords = await readJsonlRecords<BenchmarkRecord>(resolve(repositoryRoot, "data", "benchmark", "records"));

  invariant(scoredRows.length > 0, "scored dataset is empty");
  invariant(validationRecords.size === scoredRows.length, `validation/scored row mismatch: ${validationRecords.size} vs ${scoredRows.length}`);

  const artifactCommit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: repositoryRoot, encoding: "utf8" }).trim();
  const artifactRemote = execFileSync("git", ["remote", "get-url", "origin"], { cwd: repositoryRoot, encoding: "utf8" });
  const artifactRepository = githubRepositoryUrl(artifactRemote);
  const generatedPrograms = repositoryMetadata.generated_programs as Record<string, unknown> | undefined;
  invariant(generatedPrograms, "generated-program repository provenance is missing");
  invariant(typeof generatedPrograms.repository === "string", "generated-program repository URL is missing");
  invariant(typeof generatedPrograms.commit === "string", "generated-program commit is missing");

  const generatedSourceRepository = generatedPrograms.repository.replace(/\.git$/, "");
  const generatedSourceCommit = generatedPrograms.commit;
  const scoringDigest = scoringMetadata.scored_csv_sha256;
  const dataGeneratedAt = scoringMetadata.generated_at;
  invariant(typeof scoringDigest === "string", "scored CSV digest is missing");
  invariant(typeof dataGeneratedAt === "string", "scoring generation time is missing");

  const thresholds = new Map<string, CsvRow>();
  for (const row of thresholdRows) {
    invariant(row.bench && row.type, "threshold row is missing its cell identity");
    invariant(row.reviewed === "true", `threshold row is not reviewed: ${row.bench}/${row.type}`);
    const key = `${row.bench}\u0000${row.type}`;
    invariant(!thresholds.has(key), `duplicate threshold cell: ${row.bench}/${row.type}`);
    thresholds.set(key, row);
  }

  const runIds = new Set<string>();
  const runs: RunRecord[] = scoredRows.map((row) => {
    const id = recordId(row);
    invariant(!runIds.has(id), `duplicate scored run: ${id}`);
    runIds.add(id);

    const locatedValidation = validationRecords.get(id);
    invariant(locatedValidation, `validation record missing for ${id}`);
    const validation = locatedValidation.record;
    invariant(validation.benchmark === row.benchmark && validation.model === row.model && validation.backend === row.par_type,
      `validation identity mismatch for ${id}`);

    const score = parseRequiredInteger(row.overall_score, `${id}.overall_score`);
    invariant(score >= config.scoreScale.minimum && score <= config.scoreScale.maximum,
      `${id}.overall_score is outside the configured score scale`);
    const repetition = parseRequiredInteger(row.run, `${id}.run`);
    const validationStatus = parseRequiredInteger(row.validation_status, `${id}.validation_status`);
    const benchmarkSuccess = parseOptionalBoolean(row.benchmark_success, `${id}.benchmark_success`);
    const benchmarkMedianMs = parseOptionalNumber(row.benchmark_median_time, `${id}.benchmark_median_time`);
    const locatedBenchmark = benchmarkRecords.get(id);

    if (benchmarkSuccess !== null) {
      invariant(locatedBenchmark, `benchmark record missing for attempted run ${id}`);
      invariant(locatedBenchmark.record.success === benchmarkSuccess, `benchmark success mismatch for ${id}`);
    } else {
      invariant(!locatedBenchmark, `benchmark record exists for unattempted run ${id}`);
    }

    const metricTimes = locatedBenchmark?.record.metrics.map((metric) => {
      const value = metric.time;
      invariant(typeof value === "number" && Number.isFinite(value) && value > 0, `invalid benchmark time for ${id}`);
      return value;
    }) ?? [];

    if (benchmarkSuccess) {
      invariant(benchmarkMedianMs !== null && benchmarkMedianMs > 0, `successful run lacks a median time: ${id}`);
      invariant(metricTimes.length === 5, `successful run must have five benchmark measurements: ${id}`);
      const csvTimes = (row.benchmark_times ?? "").split(";").filter(Boolean).map(Number);
      invariant(csvTimes.length === metricTimes.length && csvTimes.every((value, index) => Math.abs(value - metricTimes[index]!) < 1e-9),
        `benchmark measurements disagree for ${id}`);
    } else {
      invariant(benchmarkMedianMs === null, `unsuccessful run has a median time: ${id}`);
    }

    const validationEvidenceUrl = `${artifactRepository}/blob/${artifactCommit}/${encodeRepositoryPath(locatedValidation.relativePath)}#L${locatedValidation.line}`;
    const benchmarkEvidenceUrl = locatedBenchmark
      ? `${artifactRepository}/blob/${artifactCommit}/${encodeRepositoryPath(locatedBenchmark.relativePath)}#L${locatedBenchmark.line}`
      : null;
    const sourcePath = validation.source.path;
    invariant(sourcePath, `source path is missing for ${id}`);

    return {
      id,
      modelId: row.model!,
      benchmarkId: row.benchmark!,
      backendId: row.par_type!,
      repetition,
      overallScore: score,
      scoreBandId: bandFor(score, config.scoreScale.bands).id,
      validationStatus,
      validationMessage: row.validation_err_string ?? "",
      validationStages: validation.stages,
      benchmarkSuccess,
      benchmarkMedianMs,
      benchmarkMeasurementsMs: metricTimes,
      sourceBatch: validation.source.batch,
      sourcePath,
      sourceUrl: `${generatedSourceRepository}/tree/${generatedSourceCommit}/${encodeRepositoryPath(sourcePath)}`,
      validationEvidenceUrl,
      benchmarkEvidenceUrl,
    };
  });

  invariant([...validationRecords.keys()].every((id) => runIds.has(id)), "validation records contain IDs outside scored results");
  invariant([...benchmarkRecords.keys()].every((id) => runIds.has(id)), "benchmark records contain IDs outside scored results");

  runs.sort((left, right) => left.benchmarkId.localeCompare(right.benchmarkId, "en")
    || left.backendId.localeCompare(right.backendId, "en")
    || left.modelId.localeCompare(right.modelId, "en")
    || left.repetition - right.repetition);

  const models: ModelMetadata[] = orderedEntities("models", runs.map((run) => run.modelId), config).map((model) => {
    const invocation = methodologyConfig.models[model.id];
    if (!invocation) return { ...model, invocation: null };
    invariant(harnessIds.has(invocation.harnessId), `model ${model.id} references unknown harness ${invocation.harnessId}`);
    invariant(invocation.invokedModelId.trim() !== "", `model ${model.id} has an empty invoked model ID`);
    return {
      ...model,
      invocation: {
        harnessId: invocation.harnessId,
        invokedModelId: invocation.invokedModelId,
        reasoningEffort: invocation.reasoningEffort ?? null,
      },
    };
  });
  const knownModelIds = new Set(models.map((model) => model.id));
  for (const profile of parsedCostProfiles.profiles) {
    invariant(knownModelIds.has(profile.id), `cost pricing profile has no scored model: ${profile.id}`);
  }
  const validatedCostConfig = validateCostConfig(costConfig, parsedCostProfiles.profiles, knownModelIds);
  const costAliases = validatedCostConfig.aliases;
  const costProfileMap = new Map(parsedCostProfiles.profiles.map((profile) => [profile.id, profile]));
  const costRuns = scoredRows.map((row) => costRunFromScoredRow(
    row,
    costProfileMap,
    costAliases,
    validatedCostConfig.inputTokenAccounting,
    config.scoreScale.minimum,
    config.scoreScale.maximum,
  ));
  const runsById = new Map(runs.map((run) => [run.id, run]));
  const costRunIds = new Set<string>();
  for (const costRun of costRuns) {
    invariant(!costRunIds.has(costRun.id), `duplicate generated cost run: ${costRun.id}`);
    costRunIds.add(costRun.id);
    const run = runsById.get(costRun.id);
    invariant(run, `cost run has no scored record: ${costRun.id}`);
    invariant(run.modelId === costRun.modelId
      && run.benchmarkId === costRun.benchmarkId
      && run.backendId === costRun.backendId
      && run.repetition === costRun.repetition
      && run.overallScore === costRun.overallScore,
    `cost/scored identity mismatch: ${costRun.id}`);
  }
  invariant(runs.every((run) => costRunIds.has(run.id)), "scored results contain runs outside the cost dataset");
  costRuns.sort((left, right) => left.benchmarkId.localeCompare(right.benchmarkId, "en")
    || left.backendId.localeCompare(right.backendId, "en")
    || left.modelId.localeCompare(right.modelId, "en")
    || left.repetition - right.repetition);
  reconcileCanonicalCostAggregates(costRuns, costSourceRows);
  const modelSetIds = new Set<string>();
  const modelSets: ModelSetMetadata[] = (config.modelSets ?? []).map((configuredSet) => {
    const id = requiredString(configuredSet.id, "model set ID");
    const label = requiredString(configuredSet.label, `model set ${id} label`);
    invariant(Array.isArray(configuredSet.excludeModelIds)
      && configuredSet.excludeModelIds.every((modelId) => typeof modelId === "string" && modelId.trim() !== ""),
    `model set ${id} exclusions are malformed`);
    invariant(!modelSetIds.has(id), `duplicate model set ID: ${id}`);
    modelSetIds.add(id);
    const excludedModelIds = new Set(configuredSet.excludeModelIds);
    invariant(excludedModelIds.size === configuredSet.excludeModelIds.length,
      `model set ${id} contains duplicate exclusions`);
    for (const modelId of excludedModelIds) {
      invariant(knownModelIds.has(modelId), `model set ${id} excludes unknown model ${modelId}`);
    }
    const modelIds = models.filter((model) => !excludedModelIds.has(model.id)).map((model) => model.id);
    invariant(modelIds.length > 0, `model set ${id} is empty`);
    return { id, label, modelIds };
  });
  const defaultModelSetId = config.defaultModelSetId ?? null;
  invariant(defaultModelSetId === null || modelSetIds.has(defaultModelSetId),
    `default model set is unknown: ${defaultModelSetId}`);
  const benchmarks = orderedEntities("benchmarks", runs.map((run) => run.benchmarkId), config);
  const backends = orderedEntities("backends", runs.map((run) => run.backendId), config);
  const modelOrder = new Map(models.map((entity, index) => [entity.id, index]));
  const benchmarkOrder = new Map(benchmarks.map((entity, index) => [entity.id, index]));
  const backendOrder = new Map(backends.map((entity, index) => [entity.id, index]));

  const scoreCounts = new Map<string, ScoreCubeCell>();
  const runsByCell = new Map<string, RunRecord[]>();
  for (const run of runs) {
    const cubeKey = `${run.modelId}\u0000${run.benchmarkId}\u0000${run.backendId}\u0000${run.overallScore}`;
    const existing = scoreCounts.get(cubeKey);
    if (existing) {
      existing.count += 1;
    } else {
      scoreCounts.set(cubeKey, {
        modelId: run.modelId,
        benchmarkId: run.benchmarkId,
        backendId: run.backendId,
        score: run.overallScore,
        count: 1,
      });
    }
    const cellKey = `${run.benchmarkId}\u0000${run.backendId}`;
    const cellRuns = runsByCell.get(cellKey) ?? [];
    cellRuns.push(run);
    runsByCell.set(cellKey, cellRuns);
  }

  const scoreCube = [...scoreCounts.values()].sort((left, right) =>
    (modelOrder.get(left.modelId)! - modelOrder.get(right.modelId)!)
    || (benchmarkOrder.get(left.benchmarkId)! - benchmarkOrder.get(right.benchmarkId)!)
    || (backendOrder.get(left.backendId)! - backendOrder.get(right.backendId)!)
    || left.score - right.score);

  await rm(publicDataRoot, { recursive: true, force: true });
  await rm(generatedSourceRoot, { recursive: true, force: true });
  await mkdir(publicDataRoot, { recursive: true });
  await mkdir(generatedSourceRoot, { recursive: true });

  const cells: CellDescriptor[] = [];
  const orderedCellEntries = [...runsByCell.entries()].sort(([left], [right]) => {
    const [leftBenchmark, leftBackend] = left.split("\u0000") as [string, string];
    const [rightBenchmark, rightBackend] = right.split("\u0000") as [string, string];
    return (benchmarkOrder.get(leftBenchmark)! - benchmarkOrder.get(rightBenchmark)!)
      || (backendOrder.get(leftBackend)! - backendOrder.get(rightBackend)!);
  });
  for (const [cellKey, cellRuns] of orderedCellEntries) {
    const [benchmarkId, backendId] = cellKey.split("\u0000") as [string, string];
    const successfulRuns = cellRuns.filter((run) => run.benchmarkSuccess && run.benchmarkMedianMs !== null);
    const threshold = thresholds.get(cellKey);
    invariant(successfulRuns.length === 0 || threshold, `reviewed thresholds missing for ${benchmarkId}/${backendId}`);
    const fastestMs = successfulRuns.length > 0
      ? Math.min(...successfulRuns.map((run) => run.benchmarkMedianMs!))
      : null;
    const configuredFastest = threshold ? parseOptionalNumber(threshold.fastest, `${benchmarkId}/${backendId}.fastest`) : null;
    if (fastestMs !== null && configuredFastest !== null) {
      invariant(Math.abs(fastestMs - configuredFastest) < 1e-9, `fastest threshold disagrees for ${benchmarkId}/${backendId}`);
    }
    cells.push({
      benchmarkId,
      backendId,
      runCount: cellRuns.length,
      successfulRunCount: successfulRuns.length,
      shardPath: await writeHashedAsset(`runs-${digest(cellKey).slice(0, 12)}`, cellRuns),
      thresholds: threshold && fastestMs !== null ? {
        fastestMs,
        topMs: parseOptionalNumber(threshold.top, `${benchmarkId}/${backendId}.top`)! ,
        greatMs: parseOptionalNumber(threshold.great, `${benchmarkId}/${backendId}.great`)! ,
        goodMs: parseOptionalNumber(threshold.good, `${benchmarkId}/${backendId}.good`)! ,
      } : null,
    });
  }

  const configuredPerformanceCell = config.defaultPerformanceCell;
  const defaultPerformanceCell = configuredPerformanceCell
    ? {
        benchmarkId: requiredString(configuredPerformanceCell.benchmarkId, "default performance benchmark"),
        backendId: requiredString(configuredPerformanceCell.backendId, "default performance backend"),
      }
    : (() => {
        const fallback = cells.find((cell) => cell.successfulRunCount > 0);
        return fallback ? { benchmarkId: fallback.benchmarkId, backendId: fallback.backendId } : null;
      })();
  invariant(defaultPerformanceCell === null || cells.some((cell) =>
    cell.benchmarkId === defaultPerformanceCell.benchmarkId
    && cell.backendId === defaultPerformanceCell.backendId
    && cell.successfulRunCount > 0),
  `default performance cell is unavailable or has no successful runs: ${defaultPerformanceCell?.benchmarkId}/${defaultPerformanceCell?.backendId}`);

  const scoreCubePath = await writeHashedAsset("score-cube", scoreCube);
  const costDataset: CostDataset = {
    schemaVersion: 1,
    pricingAsOf: parsedCostProfiles.pricingAsOf,
    sourceDigest: costSourceDigest,
    profiles: parsedCostProfiles.profiles,
    aliases: costAliases,
    inputTokenAccounting: validatedCostConfig.inputTokenAccounting,
    runs: costRuns,
  };
  const costDatasetPath = await writeHashedAsset("cost", costDataset);
  const runIndex = Object.fromEntries(runs.map((run) => [run.id, {
    benchmarkId: run.benchmarkId,
    backendId: run.backendId,
  } satisfies RunIndexEntry]));
  const runIndexPath = await writeHashedAsset("run-index", runIndex);
  const manifest: DatasetManifest = {
    schemaVersion: 2,
    title: config.title,
    subtitle: config.subtitle,
    artifactRepository,
    artifactCommit,
    scoringDigest,
    dataGeneratedAt,
    generatedSourceRepository,
    generatedSourceCommit,
    scoreScale: config.scoreScale,
    counts: {
      runs: runs.length,
      models: models.length,
      benchmarks: benchmarks.length,
      backends: backends.length,
    },
    models,
    modelSets,
    defaultModelSetId,
    defaultPerformanceCell,
    benchmarks,
    backends,
    methodology: {
      experimentScript: methodologyConfig.experimentScript,
      harnesses: methodologyConfig.harnesses,
      executionSystem: executionSystemFrom(evaluationManifest),
    },
    cost: {
      datasetPath: costDatasetPath,
      pricingAsOf: parsedCostProfiles.pricingAsOf,
      sourcePath: costSourcePath,
      sourceDigest: costSourceDigest,
      selectionPolicy: parsedCostProfiles.selectionPolicy,
    },
    cells,
    scoreCubePath,
    runIndexPath,
  };
  const manifestPath = await writeHashedAsset("manifest", manifest);
  await writeFile(resolve(generatedSourceRoot, "dataset.ts"),
    `// Generated by scripts/build-data.ts. Do not edit.\nexport const DATASET_MANIFEST_PATH = ${JSON.stringify(manifestPath)};\n`,
    "utf8");

  console.log(`Generated ${runs.length} runs, ${scoreCube.length} score cells, ${costRuns.length} cost records, and ${cells.length} shards.`);
}

if (resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  await buildData();
}
