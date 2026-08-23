import { useCallback, useMemo } from "react";
import { useSearchParams } from "react-router-dom";

import type { DatasetManifest, FilterState, SortOrder } from "../data/types";

const sortOrders = new Set<SortOrder>(["weakest", "strongest", "alphabetical"]);

function selectedValues(params: URLSearchParams, key: string, allowed: Set<string>): string[] {
  return [...new Set(params.getAll(key).filter((value) => allowed.has(value)))];
}

export function useFilterState(manifest: DatasetManifest) {
  const [params, setParams] = useSearchParams();
  const state = useMemo<FilterState>(() => {
    const sortValue = params.get("sort") as SortOrder | null;
    const outcome = params.get("outcome");
    const scale = params.get("scale");
    const performanceMode = params.get("mode");
    return {
      models: selectedValues(params, "model", new Set(manifest.models.map((entity) => entity.id))),
      benchmarks: selectedValues(params, "benchmark", new Set(manifest.benchmarks.map((entity) => entity.id))),
      backends: selectedValues(params, "backend", new Set(manifest.backends.map((entity) => entity.id))),
      scoreBands: selectedValues(params, "band", new Set(manifest.scoreScale.bands.map((band) => band.id))),
      outcome: outcome === "successful" || outcome === "failed" || outcome === "unavailable" ? outcome : "all",
      sort: sortValue && sortOrders.has(sortValue) ? sortValue : "weakest",
      scale: scale === "linear" ? "linear" : "log",
      performanceMode: performanceMode === "relative" ? "relative" : "absolute",
    };
  }, [manifest, params]);

  const replaceValues = useCallback((key: string, values: readonly string[]) => {
    setParams((current) => {
      const next = new URLSearchParams(current);
      next.delete(key);
      values.forEach((value) => next.append(key, value));
      next.delete("page");
      return next;
    });
  }, [setParams]);

  const replaceValue = useCallback((key: string, value: string | null, defaultValue?: string) => {
    setParams((current) => {
      const next = new URLSearchParams(current);
      if (value === null || value === "" || value === defaultValue) next.delete(key);
      else next.set(key, value);
      next.delete("page");
      return next;
    });
  }, [setParams]);

  const reset = useCallback(() => setParams(new URLSearchParams()), [setParams]);

  return { state, params, setParams, replaceValues, replaceValue, reset };
}
