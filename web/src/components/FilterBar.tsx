import type { ReactNode } from "react";

import type { DatasetManifest, FilterState } from "../data/types";
import { getDefaultModelSet, selectionsMatch } from "../state/modelSets";
import { FilterMenu } from "./FilterMenu";

export function FilterBar({
  manifest,
  filters,
  onModels,
  onBenchmarks,
  onBackends,
  onReset,
  additionalActiveCount = 0,
  resultSummary,
  benchmarkControl,
  backendControl,
  baselineBenchmarks = [],
  baselineBackends = [],
  children,
}: {
  manifest: DatasetManifest;
  filters: FilterState;
  onModels: (values: string[]) => void;
  onBenchmarks: (values: string[]) => void;
  onBackends: (values: string[]) => void;
  onReset: () => void;
  additionalActiveCount?: number;
  resultSummary?: ReactNode;
  benchmarkControl?: ReactNode;
  backendControl?: ReactNode;
  baselineBenchmarks?: readonly string[];
  baselineBackends?: readonly string[];
  children?: ReactNode;
}) {
  const defaultModelSet = getDefaultModelSet(manifest);
  const activeModelCount = defaultModelSet && selectionsMatch(filters.models, defaultModelSet.modelIds)
    ? 0
    : filters.models.length === 0 && defaultModelSet
      ? 1
      : filters.models.length;
  const activeBenchmarkCount = selectionsMatch(filters.benchmarks, baselineBenchmarks) ? 0 : filters.benchmarks.length;
  const activeBackendCount = selectionsMatch(filters.backends, baselineBackends) ? 0 : filters.backends.length;
  const activeCount = activeModelCount + activeBenchmarkCount + activeBackendCount + filters.scoreBands.length
    + (filters.outcome === "all" ? 0 : 1) + additionalActiveCount;
  return (
    <section className="filter-bar" aria-label="Data filters">
      <div className="filter-group">
        <FilterMenu
          label="Models"
          entities={manifest.models}
          selected={filters.models}
          onChange={onModels}
          namedSelection={defaultModelSet ? { label: defaultModelSet.label, values: defaultModelSet.modelIds } : undefined}
        />
        {benchmarkControl ?? <FilterMenu label="Benchmarks" entities={manifest.benchmarks} selected={filters.benchmarks} onChange={onBenchmarks} />}
        {backendControl ?? <FilterMenu label="Backends" entities={manifest.backends} selected={filters.backends} onChange={onBackends} />}
        {children}
      </div>
      <div className="filter-bar-end">
        {resultSummary}
        <button className="reset-button" type="button" onClick={onReset} disabled={activeCount === 0}>
          Reset{activeCount > 0 ? ` (${activeCount})` : ""}
        </button>
      </div>
    </section>
  );
}
