import type { DatasetManifest, ModelSetMetadata } from "../data/types";

export function selectionsMatch(left: readonly string[], right: readonly string[]): boolean {
  if (left.length !== right.length) return false;
  const rightSet = new Set(right);
  return rightSet.size === right.length && left.every((value) => rightSet.has(value));
}

export function getDefaultModelSet(manifest: DatasetManifest): ModelSetMetadata | null {
  if (manifest.defaultModelSetId === null) return null;
  return manifest.modelSets.find((modelSet) => modelSet.id === manifest.defaultModelSetId) ?? null;
}
