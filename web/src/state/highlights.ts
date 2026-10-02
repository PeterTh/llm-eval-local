import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";

export interface HighlightState {
  modelIds: string[];
  benchmarkIds: string[];
  runIds: string[];
}

export const HIGHLIGHT_PARAMS = {
  modelIds: "highlight-model",
  benchmarkIds: "highlight-benchmark",
  runIds: "highlight-run",
} as const;
export type HighlightKind = keyof HighlightState;

export function readHighlights(params: URLSearchParams): HighlightState {
  const values = (key: string) => [...new Set(params.getAll(key).filter(Boolean))];
  return { modelIds: values(HIGHLIGHT_PARAMS.modelIds), benchmarkIds: values(HIGHLIGHT_PARAMS.benchmarkIds), runIds: values(HIGHLIGHT_PARAMS.runIds) };
}

export function copyHighlights(source: URLSearchParams, target = new URLSearchParams()): URLSearchParams {
  const state = readHighlights(source);
  for (const kind of Object.keys(HIGHLIGHT_PARAMS) as HighlightKind[]) {
    target.delete(HIGHLIGHT_PARAMS[kind]);
    state[kind].forEach((id) => target.append(HIGHLIGHT_PARAMS[kind], id));
  }
  return target;
}

export function toggleHighlight(params: URLSearchParams, kind: HighlightKind, id: string): URLSearchParams {
  const next = new URLSearchParams(params);
  const ids = new Set(readHighlights(params)[kind]);
  if (ids.has(id)) ids.delete(id);
  else if (id) ids.add(id);
  next.delete(HIGHLIGHT_PARAMS[kind]);
  [...ids].sort().forEach((value) => next.append(HIGHLIGHT_PARAMS[kind], value));
  return next;
}

export function useHighlightState(kind: HighlightKind, visibleIds: readonly string[]) {
  const [params, setParams] = useSearchParams();
  const [active, setActive] = useState(false);
  const ids = useMemo(() => readHighlights(params)[kind], [kind, params]);
  const selected = useMemo(() => new Set(ids), [ids]);
  const visible = new Set(visibleIds);
  const hiddenCount = ids.filter((id) => !visible.has(id)).length;
  const toggle = useCallback((id: string) => {
    setParams((current) => toggleHighlight(current, kind, id));
  }, [kind, setParams]);
  const clear = useCallback(() => {
    setParams((current) => {
      const next = new URLSearchParams(current);
      next.delete(HIGHLIGHT_PARAMS[kind]);
      return next;
    });
  }, [kind, setParams]);
  useEffect(() => {
    if (!active) return;
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !event.defaultPrevented) setActive(false);
    };
    document.addEventListener("keydown", escape);
    return () => document.removeEventListener("keydown", escape);
  }, [active]);
  return { active, setActive, ids, selected, hiddenCount, toggle, clear };
}

export type HighlightSelection = ReturnType<typeof useHighlightState>;

export function modelHighlightId(datum: Record<string, unknown>): string | null {
  return typeof datum.modelId === "string" ? datum.modelId : null;
}

export function runHighlightId(datum: Record<string, unknown>): string | null {
  return typeof datum.runId === "string" ? datum.runId : null;
}
