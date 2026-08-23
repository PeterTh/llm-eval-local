import type { ReactNode } from "react";

import type { DatasetManifest, FilterState } from "../data/types";
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
  children?: ReactNode;
}) {
  const activeCount = filters.models.length + filters.benchmarks.length + filters.backends.length + filters.scoreBands.length
    + (filters.outcome === "all" ? 0 : 1) + additionalActiveCount;
  return (
    <section className="filter-bar" aria-label="Data filters">
      <div className="filter-group">
        <FilterMenu label="Models" entities={manifest.models} selected={filters.models} onChange={onModels} />
        <FilterMenu label="Benchmarks" entities={manifest.benchmarks} selected={filters.benchmarks} onChange={onBenchmarks} />
        <FilterMenu label="Backends" entities={manifest.backends} selected={filters.backends} onChange={onBackends} />
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
