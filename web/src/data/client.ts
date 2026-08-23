import { DATASET_MANIFEST_PATH } from "../generated/dataset";
import {
  datasetManifestSchema,
  runIndexSchema,
  runShardSchema,
  scoreCubeSchema,
} from "./schema";
import type {
  CellDescriptor,
  DatasetManifest,
  RunIndexEntry,
  RunRecord,
  ScoreCubeCell,
} from "./types";

const shardCache = new Map<string, Promise<RunRecord[]>>();
let runIndexPromise: Promise<Record<string, RunIndexEntry>> | null = null;

function assetUrl(path: string): string {
  const base = import.meta.env.BASE_URL.endsWith("/") ? import.meta.env.BASE_URL : `${import.meta.env.BASE_URL}/`;
  return `${base}${path.replace(/^\//, "")}`;
}

async function fetchJson(path: string): Promise<unknown> {
  const response = await fetch(assetUrl(path));
  if (!response.ok) {
    throw new Error(`Could not load ${path} (${response.status})`);
  }
  return response.json() as Promise<unknown>;
}

export async function loadDataset(): Promise<{
  manifest: DatasetManifest;
  scoreCube: ScoreCubeCell[];
}> {
  const manifest = datasetManifestSchema.parse(await fetchJson(DATASET_MANIFEST_PATH));
  const scoreCube = scoreCubeSchema.parse(await fetchJson(manifest.scoreCubePath));
  return { manifest, scoreCube };
}

export function loadCellRuns(cell: CellDescriptor): Promise<RunRecord[]> {
  let request = shardCache.get(cell.shardPath);
  if (!request) {
    request = fetchJson(cell.shardPath).then((value) => runShardSchema.parse(value));
    shardCache.set(cell.shardPath, request);
  }
  return request;
}

export async function loadRuns(
  manifest: DatasetManifest,
  benchmarks: readonly string[] = [],
  backends: readonly string[] = [],
): Promise<RunRecord[]> {
  const benchmarkFilter = new Set(benchmarks);
  const backendFilter = new Set(backends);
  const cells = manifest.cells.filter((cell) =>
    (benchmarkFilter.size === 0 || benchmarkFilter.has(cell.benchmarkId))
    && (backendFilter.size === 0 || backendFilter.has(cell.backendId)));
  return (await Promise.all(cells.map(loadCellRuns))).flat();
}

export async function loadRunById(manifest: DatasetManifest, id: string): Promise<RunRecord | null> {
  runIndexPromise ??= fetchJson(manifest.runIndexPath).then((value) => runIndexSchema.parse(value));
  const index = await runIndexPromise;
  const location = index[id];
  if (!location) return null;
  const cell = manifest.cells.find((candidate) =>
    candidate.benchmarkId === location.benchmarkId && candidate.backendId === location.backendId);
  if (!cell) return null;
  return (await loadCellRuns(cell)).find((run) => run.id === id) ?? null;
}

export function clearDataCacheForTests(): void {
  shardCache.clear();
  runIndexPromise = null;
}
