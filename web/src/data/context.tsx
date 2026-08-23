import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

import { loadDataset } from "./client";
import type { DatasetManifest, ScoreCubeCell } from "./types";

interface DatasetContextValue {
  manifest: DatasetManifest;
  scoreCube: ScoreCubeCell[];
  labels: {
    models: Map<string, string>;
    benchmarks: Map<string, string>;
    backends: Map<string, string>;
  };
}

const DatasetContext = createContext<DatasetContextValue | null>(null);

export function DatasetProvider({ children }: { children: ReactNode }) {
  const [dataset, setDataset] = useState<{ manifest: DatasetManifest; scoreCube: ScoreCubeCell[] } | null>(null);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    loadDataset().then((loaded) => {
      if (active) setDataset(loaded);
    }).catch((reason: unknown) => {
      if (active) setError(reason instanceof Error ? reason : new Error(String(reason)));
    });
    return () => { active = false; };
  }, []);

  const value = useMemo<DatasetContextValue | null>(() => {
    if (!dataset) return null;
    return {
      ...dataset,
      labels: {
        models: new Map(dataset.manifest.models.map((entity) => [entity.id, entity.label])),
        benchmarks: new Map(dataset.manifest.benchmarks.map((entity) => [entity.id, entity.label])),
        backends: new Map(dataset.manifest.backends.map((entity) => [entity.id, entity.label])),
      },
    };
  }, [dataset]);

  if (error) {
    return (
      <main className="fatal-state">
        <p className="eyebrow">Dataset unavailable</p>
        <h1>The evaluation data could not be loaded.</h1>
        <p>{error.message}</p>
        <button type="button" onClick={() => window.location.reload()}>Try again</button>
      </main>
    );
  }
  if (!value) {
    return (
      <main className="loading-state" aria-live="polite">
        <div className="loading-mark" aria-hidden="true" />
        <p>Loading evaluation data…</p>
      </main>
    );
  }
  return <DatasetContext.Provider value={value}>{children}</DatasetContext.Provider>;
}

export function useDataset(): DatasetContextValue {
  const value = useContext(DatasetContext);
  if (!value) throw new Error("useDataset must be used inside DatasetProvider");
  return value;
}
