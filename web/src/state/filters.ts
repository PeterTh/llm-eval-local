import { useCallback, useMemo } from "react";
import { useSearchParams } from "react-router-dom";

import type { DatasetManifest, FilterState, SortOrder } from "../data/types";
import { getDefaultModelSet, selectionsMatch } from "./modelSets";

const sortOrders = new Set<SortOrder>(["weakest", "strongest", "alphabetical"]);

function selectedValues(params: URLSearchParams, key: string, allowed: Set<string>): string[] {
  return [...new Set(params.getAll(key).filter((value) => allowed.has(value)))];
}

export function useFilterState(manifest: DatasetManifest) {
  const [params, setParams] = useSearchParams();
  const defaultModelSet = useMemo(() => getDefaultModelSet(manifest), [manifest]);
  const state = useMemo<FilterState>(() => {
    const sortValue = params.get("sort") as SortOrder | null;
    const outcome = params.get("outcome");
    const scale = params.get("scale");
    const performanceMode = params.get("mode");
    const allowedModels = new Set(manifest.models.map((entity) => entity.id));
    const requestedModelSet = params.get("model-set");
    const namedModelSet = requestedModelSet && requestedModelSet !== "all"
      ? manifest.modelSets.find((modelSet) => modelSet.id === requestedModelSet)
      : null;
    const models = params.has("model")
      ? selectedValues(params, "model", allowedModels)
      : requestedModelSet === "all"
        ? []
        : (namedModelSet ?? defaultModelSet)?.modelIds.filter((modelId) => allowedModels.has(modelId)) ?? [];
    return {
      models,
      benchmarks: selectedValues(params, "benchmark", new Set(manifest.benchmarks.map((entity) => entity.id))),
      backends: selectedValues(params, "backend", new Set(manifest.backends.map((entity) => entity.id))),
      scoreBands: selectedValues(params, "band", new Set(manifest.scoreScale.bands.map((band) => band.id))),
      outcome: outcome === "successful" || outcome === "failed" || outcome === "unavailable" ? outcome : "all",
      sort: sortValue && sortOrders.has(sortValue) ? sortValue : "weakest",
      scale: scale === "linear" ? "linear" : "log",
      performanceMode: performanceMode === "relative" ? "relative" : "absolute",
    };
  }, [defaultModelSet, manifest, params]);

  const replaceValues = useCallback((key: string, values: readonly string[]) => {
    setParams((current) => {
      const next = new URLSearchParams(current);
      next.delete(key);
      if (key === "model") {
        next.delete("model-set");
        if (defaultModelSet && selectionsMatch(values, defaultModelSet.modelIds)) {
          // The default set is the canonical omitted URL state.
        } else if (values.length === 0 && defaultModelSet) {
          next.set("model-set", "all");
        } else {
          values.forEach((value) => next.append(key, value));
        }
      } else {
        values.forEach((value) => next.append(key, value));
      }
      next.delete("page");
      return next;
    });
  }, [defaultModelSet, setParams]);

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
