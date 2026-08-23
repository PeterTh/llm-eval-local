import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import type { VisualizationSpec } from "vega-embed";

import {
  analyzePerformance,
  resolvePerformanceCell,
  type PerformanceOrder,
} from "../analysis/performance";
import { FilterBar } from "../components/FilterBar";
import { VegaChart } from "../components/VegaChart";
import { loadCellRuns } from "../data/client";
import { useDataset } from "../data/context";
import type { CellDescriptor, RunRecord } from "../data/types";
import { useFilterState } from "../state/filters";
import { downloadText, runsToCsv } from "../utils/csv";
import { formatMilliseconds } from "../utils/format";
import { useMediaQuery } from "../utils/media";

const PERFORMANCE_POINT_SHAPES = ["circle", "square", "triangle-up", "diamond"] as const;

function performanceOrder(params: URLSearchParams): PerformanceOrder {
  const value = params.get("order");
  return value === "slowest" || value === "alphabetical" ? value : "fastest";
}

function runDetailPath(runId: string, params: URLSearchParams): string {
  const query = new URLSearchParams(params);
  query.set("from", "performance");
  return `/run/${encodeURIComponent(runId)}?${query}`;
}

function modelRunsPath(modelId: string, cell: CellDescriptor): string {
  const query = new URLSearchParams();
  query.append("model", modelId);
  query.append("benchmark", cell.benchmarkId);
  query.append("backend", cell.backendId);
  return `/runs?${query}`;
}

export function PerformanceView() {
  const { manifest, labels } = useDataset();
  const { state, params, setParams, replaceValues, replaceValue, reset } = useFilterState(manifest);
  const navigate = useNavigate();
  const [runs, setRuns] = useState<RunRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [retry, setRetry] = useState(0);
  const [exporting, setExporting] = useState(false);
  const isNarrow = useMediaQuery("(max-width: 600px)");
  const isDark = useMediaQuery("(prefers-color-scheme: dark)");
  const defaultCell = useMemo(() => resolvePerformanceCell(manifest, [], []), [manifest]);
  const activeCell = useMemo(
    () => resolvePerformanceCell(manifest, state.benchmarks, state.backends),
    [manifest, state.backends, state.benchmarks],
  );
  const requestedFocus = params.get("focus");
  const focusedModelId = requestedFocus && manifest.models.some((model) => model.id === requestedFocus)
    ? requestedFocus
    : null;
  const activeModelIds = useMemo(() => {
    if (!focusedModelId || state.models.length === 0 || state.models.includes(focusedModelId)) {
      return state.models;
    }
    return [...state.models, focusedModelId];
  }, [focusedModelId, state.models]);
  const analysisState = useMemo(() => ({ ...state, models: activeModelIds }), [activeModelIds, state]);
  const order = performanceOrder(params);
  const showMeasurementRanges = params.get("ranges") === "shown";
  const cellKey = activeCell ? `${activeCell.benchmarkId}\0${activeCell.backendId}` : "";

  useEffect(() => {
    let active = true;
    if (!activeCell) {
      setRuns([]);
      setLoading(false);
      setError(null);
      return () => { active = false; };
    }
    setLoading(true);
    setError(null);
    loadCellRuns(activeCell).then((loaded) => {
      if (active) setRuns(loaded);
    }).catch((reason: unknown) => {
      if (active) setError(reason instanceof Error ? reason : new Error(String(reason)));
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => { active = false; };
    // The stable cell key prevents unrelated filter controls from refetching the shard.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [manifest, cellKey, retry]);

  const analysis = useMemo(
    () => analyzePerformance(runs, manifest, analysisState, order),
    [analysisState, manifest, order, runs],
  );
  const activeRuns = useMemo(() => {
    const selectedModels = new Set(analysisState.models);
    return runs.filter((run) => selectedModels.size === 0 || selectedModels.has(run.modelId));
  }, [analysisState.models, runs]);
  const modelOrder = analysis.models.map((model) => model.modelId);
  const chartHeight = Math.max(isNarrow ? 150 : 170, analysis.models.length * (isNarrow ? 40 : 46));
  const rowStep = chartHeight / Math.max(1, analysis.models.length);
  const points = useMemo(() => analysis.models.flatMap((model, modelIndex) => {
    const orderedPoints = [...model.points].sort((left, right) =>
      left.repetition - right.repetition || left.runId.localeCompare(right.runId, "en"));
    const shapeIndex = modelIndex % PERFORMANCE_POINT_SHAPES.length;
    const pointShape = PERFORMANCE_POINT_SHAPES[shapeIndex];
    const sizeMultiplier = pointShape === "triangle-up" ? 1.4 : pointShape === "diamond" ? 1.28 : 1;
    const pointInset = isNarrow ? 4 : 5;
    const availableRowHeight = Math.max(0, rowStep - pointInset * 2);
    return orderedPoints.map((point, index) => ({
      ...point,
      rowOffset: orderedPoints.length === 1
        ? rowStep / 2
        : pointInset + availableRowHeight * index / (orderedPoints.length - 1),
      pointShape,
      pointSize: Math.round((isNarrow ? 48 : 65) * sizeMultiplier),
    }));
  }), [analysis.models, isNarrow, rowStep]);
  const modelRows = useMemo(() => analysis.models.map((model, index) => ({
    ...model,
    rowIndex: index,
    medianLabel: formatMilliseconds(model.medianMs),
  })), [analysis.models]);
  const plottedValues = points.flatMap((point) => showMeasurementRanges
    ? [point.plotMinimum, point.plotMaximum]
    : [point.plotValue]);
  const plottedMinimum = plottedValues.length > 0 ? Math.min(...plottedValues) : 1;
  const plottedMaximum = plottedValues.length > 0 ? Math.max(...plottedValues) : 10;
  const safeMaximum = plottedMaximum > plottedMinimum ? plottedMaximum : plottedMinimum * 1.1;
  const lowerMagnitude = 10 ** Math.floor(Math.log10(plottedMinimum));
  const logDomainMinimum = plottedMinimum / lowerMagnitude <= 1.5
    ? lowerMagnitude
    : plottedMinimum / 1.08;
  const xDomain: [number, number] = state.scale === "log"
    ? [logDomainMinimum, safeMaximum * 1.08]
    : [0, safeMaximum * 1.05];
  const xScale = state.scale === "log"
    ? {
        type: "log" as const,
        domain: xDomain,
        nice: false,
        zero: false,
      }
    : {
        type: "linear" as const,
        domain: xDomain,
        nice: true,
        zero: true,
      };
  const bandRows = modelRows.filter((model) => model.rowIndex % 2 === 1).map((model) => ({
    ...model,
    bandMinimum: xDomain[0],
    bandMaximum: xDomain[1],
  }));
  const focusedRows = modelRows.filter((model) => model.modelId === focusedModelId).map((model) => ({
    ...model,
    bandMinimum: xDomain[0],
    bandMaximum: xDomain[1],
  }));

  const xAxis = state.performanceMode === "relative"
    ? {
        title: "Runtime relative to fastest full-cell run",
        labelExpr: "format(datum.value, '.3~g') + '×'",
      }
    : {
        title: "Median execution time (ms)",
        format: "~s",
      };
  const rangeLayer = showMeasurementRanges ? [{
    mark: {
      type: "rule" as const,
      color: isDark ? "#71828a" : "#9ba6aa",
      opacity: 0.72,
      strokeWidth: isNarrow ? 1.4 : 1.7,
    },
    encoding: {
      x: { field: "plotMinimum", type: "quantitative" as const },
      x2: { field: "plotMaximum" },
      yOffset: { field: "rowOffset", type: "quantitative" as const, scale: null },
    },
  }] : [];
  const spec = useMemo<VisualizationSpec>(() => ({
    $schema: "https://vega.github.io/schema/vega-lite/v6.json",
    width: "container",
    height: chartHeight,
    autosize: { type: "fit-x", contains: "padding", resize: true },
    padding: { left: 4, right: 24, top: 8, bottom: 6 },
    data: { values: points },
    encoding: {
      y: {
        field: "modelId", type: "nominal", sort: modelOrder,
        scale: { domain: modelOrder },
        axis: {
          title: null,
          labelLimit: isNarrow ? 150 : 230,
          labelPadding: 10,
          labelFontSize: isNarrow ? 12 : 14,
          labelFontWeight: 520,
          labelOpacity: 0,
          ticks: false,
          domain: false,
        },
      },
      x: {
        field: "plotValue", type: "quantitative",
        scale: xScale,
        axis: {
          ...xAxis,
          titleFontSize: isNarrow ? 12 : 14,
          labelFontSize: isNarrow ? 12 : 13,
          tickCount: isNarrow ? 4 : 8,
          grid: true,
        },
      },
    },
    layer: [
      {
        name: "performance_row_bands",
        data: { values: bandRows },
        mark: {
          type: "rect",
          color: isDark ? "#8fb8f5" : "#0b5bbb",
          opacity: isDark ? 0.04 : 0.035,
          aria: false,
        },
        encoding: {
          x: { field: "bandMinimum", type: "quantitative" },
          x2: { field: "bandMaximum" },
        },
      },
      {
        name: "performance_focused_row",
        data: { values: focusedRows },
        mark: {
          type: "rect",
          color: isDark ? "#8fb8f5" : "#0b5bbb",
          opacity: isDark ? 0.13 : 0.1,
          aria: false,
        },
        encoding: {
          x: { field: "bandMinimum", type: "quantitative" },
          x2: { field: "bandMaximum" },
        },
      },
      ...rangeLayer,
      {
        name: "performance_model_medians",
        data: { values: modelRows.filter((model) => model.plotMedian !== null) },
        mark: {
          type: "tick",
          orient: "vertical",
          size: Math.max(12, rowStep - 2),
          thickness: isNarrow ? 1.6 : 1.9,
          color: isDark ? "#f3f7fc" : "#173f70",
          opacity: 0.88,
        },
        encoding: {
          x: { field: "plotMedian", type: "quantitative" },
          tooltip: [
            { field: "modelLabel", title: "Model" },
            { field: "successfulRunCount", title: "Successful runs", format: "d" },
            { field: "attemptedRunCount", title: "Attempted runs", format: "d" },
            { field: "medianLabel", title: "Model median" },
            { field: "relativeMedian", title: "Relative median", format: ".3~f" },
          ],
        },
      },
      {
        mark: {
          type: "point",
          filled: true,
          color: isDark ? "#8fb8f5" : "#0b5bbb",
          opacity: 0.78,
          stroke: isDark ? "#182126" : "#ffffff",
          strokeWidth: 0.9,
          cursor: "pointer",
        },
        encoding: {
          yOffset: { field: "rowOffset", type: "quantitative", scale: null },
          shape: { field: "pointShape", type: "nominal", scale: null, legend: null },
          size: { field: "pointSize", type: "quantitative", scale: null, legend: null },
          description: { field: "accessibleDescription", type: "nominal" },
          key: { field: "runId", type: "nominal" },
          tooltip: [
            { field: "runId", title: "Run" },
            { field: "modelLabel", title: "Model" },
            { field: "repetition", title: "Repetition", format: "d" },
            { field: "medianLabel", title: "Median" },
            { field: "measurementsLabel", title: "Measurements" },
            { field: "relativeToFastest", title: "Relative to fastest", format: ".3~f" },
            { field: "sourceAvailabilityLabel", title: "Source evidence" },
          ],
        },
      },
      {
        data: { values: modelRows },
        mark: {
          type: "text",
          align: "right",
          baseline: "middle",
          dx: -10,
          color: isDark ? "#c1cbc9" : "#49535d",
          cursor: "help",
          clip: false,
          fontSize: isNarrow ? 12 : 14,
          fontWeight: 520,
        },
        encoding: {
          x: { value: 0 },
          y: { field: "modelId", type: "nominal", sort: modelOrder, scale: { domain: modelOrder } },
          color: { value: isDark ? "#c1cbc9" : "#49535d" },
          text: { field: "modelLabel", type: "nominal" },
          tooltip: [
            { field: "modelLabel", title: "Model" },
            { field: "modelHarnessLabel", title: "Agent harness" },
            { field: "modelInvocationLabel", title: "Invocation" },
            { field: "successfulRunCount", title: "Successful runs", format: "d" },
            { field: "attemptedRunCount", title: "Attempted runs", format: "d" },
            { field: "medianLabel", title: "Median" },
          ],
        },
      },
      {
        data: { values: modelRows.filter((model) => model.plotMedian === null) },
        mark: {
          type: "text",
          align: "left",
          baseline: "middle",
          color: isDark ? "#97a5a7" : "#68747c",
          fontSize: isNarrow ? 12 : 13,
          fontStyle: "italic",
        },
        encoding: {
          x: { value: 7 },
          y: { field: "modelId", type: "nominal", sort: modelOrder, scale: { domain: modelOrder } },
          text: { field: "zeroSuccessLabel", type: "nominal" },
        },
      },
    ],
    config: {
      background: isDark ? "#182126" : "#ffffff",
      font: "Roboto Condensed Variable, Roboto Condensed, Arial Narrow, sans-serif",
      axis: {
        labelColor: isDark ? "#c1cbc9" : "#49535d",
        titleColor: isDark ? "#c1cbc9" : "#49535d",
        gridColor: isDark ? "#334147" : "#dfe2e1",
        gridOpacity: 0.75,
      },
      view: { stroke: null },
    },
  }) as VisualizationSpec, [bandRows, chartHeight, focusedRows, isDark, isNarrow, modelOrder, modelRows, points, rangeLayer, rowStep, xAxis, xScale]);

  const setCell = useCallback((cell: CellDescriptor) => {
    setParams((current) => {
      const next = new URLSearchParams(current);
      next.delete("benchmark");
      next.delete("backend");
      if (!defaultCell
        || cell.benchmarkId !== defaultCell.benchmarkId
        || cell.backendId !== defaultCell.backendId) {
        next.append("benchmark", cell.benchmarkId);
        next.append("backend", cell.backendId);
      }
      next.delete("page");
      return next;
    });
  }, [defaultCell, setParams]);

  const chooseBenchmark = useCallback((benchmarkId: string) => {
    const nextCell = manifest.cells.find((cell) =>
      cell.benchmarkId === benchmarkId && cell.backendId === activeCell?.backendId)
      ?? manifest.cells.find((cell) => cell.benchmarkId === benchmarkId);
    if (nextCell) setCell(nextCell);
  }, [activeCell?.backendId, manifest.cells, setCell]);

  const chooseBackend = useCallback((backendId: string) => {
    const nextCell = manifest.cells.find((cell) =>
      cell.benchmarkId === activeCell?.benchmarkId && cell.backendId === backendId);
    if (nextCell) setCell(nextCell);
  }, [activeCell?.benchmarkId, manifest.cells, setCell]);

  const openPoint = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.runId === "string") {
      navigate(runDetailPath(datum.runId, new URLSearchParams(params)));
    }
  }, [navigate, params]);

  async function exportRecords(): Promise<void> {
    setExporting(true);
    try {
      downloadText("llm-eval-performance-cell.csv", runsToCsv(activeRuns), "text/csv;charset=utf-8");
    } finally {
      setExporting(false);
    }
  }

  const availableBenchmarks = manifest.benchmarks.filter((benchmark) =>
    manifest.cells.some((cell) => cell.benchmarkId === benchmark.id));
  const availableBackends = manifest.backends.filter((backend) =>
    manifest.cells.some((cell) =>
      cell.benchmarkId === activeCell?.benchmarkId && cell.backendId === backend.id));
  const activeFilters = {
    ...analysisState,
    benchmarks: activeCell ? [activeCell.benchmarkId] : state.benchmarks,
    backends: activeCell ? [activeCell.backendId] : state.backends,
    scoreBands: [],
    outcome: "all" as const,
  };
  const additionalActiveCount = (order === "fastest" ? 0 : 1)
    + (state.scale === "log" ? 0 : 1)
    + (state.performanceMode === "absolute" ? 0 : 1)
    + (showMeasurementRanges ? 1 : 0);
  const benchmarkLabel = activeCell ? labels.benchmarks.get(activeCell.benchmarkId) ?? activeCell.benchmarkId : "Unavailable";
  const backendLabel = activeCell ? labels.backends.get(activeCell.backendId) ?? activeCell.backendId : "Unavailable";

  return (
    <main id="main-content" className="page-shell">
      <header className="view-summary">
        <h1 className="sr-only">Performance</h1>
        <p>Successful benchmark measurements are shown by model for one benchmark and parallelization target.</p>
      </header>

      <FilterBar
        manifest={manifest}
        filters={activeFilters}
        onModels={(values) => replaceValues("model", values)}
        onBenchmarks={() => undefined}
        onBackends={() => undefined}
        onReset={reset}
        baselineBenchmarks={defaultCell ? [defaultCell.benchmarkId] : []}
        baselineBackends={defaultCell ? [defaultCell.backendId] : []}
        additionalActiveCount={additionalActiveCount}
        benchmarkControl={(
          <label className="inline-select">
            <span>Benchmark</span>
            <select aria-label="Benchmark" value={activeCell?.benchmarkId ?? ""} onChange={(event) => chooseBenchmark(event.target.value)}>
              {availableBenchmarks.map((benchmark) => <option key={benchmark.id} value={benchmark.id}>{benchmark.label}</option>)}
            </select>
          </label>
        )}
        backendControl={(
          <label className="inline-select compact-inline-select">
            <span>Target</span>
            <select aria-label="Target" value={activeCell?.backendId ?? ""} onChange={(event) => chooseBackend(event.target.value)}>
              {availableBackends.map((backend) => <option key={backend.id} value={backend.id}>{backend.label}</option>)}
            </select>
          </label>
        )}
        resultSummary={(
          <div className="filter-result-summary" aria-label="Current performance selection summary">
            <span><strong>{loading ? "…" : analysis.models.length}</strong> {analysis.models.length === 1 ? "model" : "models"}</span>
            <span><strong>{loading ? "…" : analysis.successfulRunCount}</strong> timed</span>
            <span><strong>{loading ? "…" : analysis.omittedRunCount}</strong> omitted</span>
          </div>
        )}
      >
        <label className="inline-select">
          <span>Order</span>
          <select aria-label="Order" value={order} onChange={(event) => replaceValue("order", event.target.value, "fastest")}>
            <option value="fastest">Fastest to slowest</option>
            <option value="slowest">Slowest to fastest</option>
            <option value="alphabetical">Alphabetical</option>
          </select>
        </label>
        <label className="inline-select compact-inline-select">
          <span>Values</span>
          <select aria-label="Values" value={state.performanceMode} onChange={(event) => replaceValue("mode", event.target.value, "absolute")}>
            <option value="absolute">Milliseconds</option>
            <option value="relative">× fastest</option>
          </select>
        </label>
        <label className="inline-select compact-inline-select">
          <span>Scale</span>
          <select aria-label="Scale" value={state.scale} onChange={(event) => replaceValue("scale", event.target.value, "log")}>
            <option value="log">Logarithmic</option>
            <option value="linear">Linear</option>
          </select>
        </label>
        <label className="inline-check">
          <input
            type="checkbox"
            checked={showMeasurementRanges}
            onChange={(event) => replaceValue("ranges", event.target.checked ? "shown" : null)}
          />
          <span>Show measurement ranges</span>
        </label>
      </FilterBar>

      <section className="analysis-panel performance-analysis">
        <header className="panel-heading">
          <div>
            <h2>{benchmarkLabel} · {backendLabel}</h2>
            <p>Points are successful program-run medians; shape identifies the model row, and vertical rules mark model medians.</p>
          </div>
          <button className="secondary-button" type="button" disabled={exporting || loading || activeRuns.length === 0} onClick={() => void exportRecords()}>
            {exporting ? "Preparing…" : "Export active records · CSV"}
          </button>
        </header>

        {!activeCell ? (
          <div className="empty-state">
            <p className="eyebrow">Unavailable cell</p>
            <h2>No observed benchmark cell matches this selection.</h2>
            <button className="secondary-button" type="button" onClick={reset}>Use the default cell</button>
          </div>
        ) : loading ? (
          <div className="analysis-loading" aria-live="polite"><i /><i /><i /><span>Loading benchmark measurements…</span></div>
        ) : error ? (
          <div className="empty-state">
            <p className="eyebrow">Data error</p>
            <h2>The performance observations could not be loaded.</h2>
            <p>{error.message}</p>
            <button className="secondary-button" type="button" onClick={() => setRetry((value) => value + 1)}>Try again</button>
          </div>
        ) : analysis.successfulRunCount > 0 ? (
          <>
            <VegaChart
              spec={spec}
              ariaLabel={`Performance chart for ${benchmarkLabel}, ${backendLabel}, ${analysis.models.length} models, and ${analysis.successfulRunCount} successful runs${focusedModelId ? `; ${labels.models.get(focusedModelId) ?? focusedModelId} highlighted` : ""}`}
              onDatumClick={openPoint}
              interactiveMarkSelector='[aria-label^="Run "]'
            />
            <p className="chart-footnote">
              {analysis.omittedRunCount} active {analysis.omittedRunCount === 1 ? "run is" : "runs are"} omitted:
              {` ${analysis.benchmarkFailureCount} benchmark ${analysis.benchmarkFailureCount === 1 ? "failure" : "failures"} and ${analysis.notBenchmarkedCount} not benchmarked.`}
              {analysis.fullCellFastestMs !== null && ` Relative values use the full-cell fastest median of ${formatMilliseconds(analysis.fullCellFastestMs)}.`}
              {showMeasurementRanges && " Horizontal lines span the recorded measurements."}
            </p>
          </>
        ) : (
          <div className="empty-state">
            <p className="eyebrow">No successful timings</p>
            <h2>The active models have no successful benchmark runs in this cell.</h2>
            <p>{analysis.omittedRunCount} attempted {analysis.omittedRunCount === 1 ? "run was" : "runs were"} omitted.</p>
          </div>
        )}
      </section>

      {!loading && !error && activeCell && analysis.models.length > 0 && (
        <details className="accessible-data">
          <summary>Accessible performance statistics</summary>
          <div className="table-scroll">
            <table>
              <caption>Performance statistics for {benchmarkLabel} and {backendLabel}</caption>
              <thead><tr><th scope="col">Model</th><th scope="col">Attempted</th><th scope="col">Timed</th><th scope="col">Omitted</th><th scope="col">Median</th><th scope="col">Relative median</th><th scope="col">Records</th></tr></thead>
              <tbody>
                {analysis.models.map((model) => (
                  <tr key={model.modelId}>
                    <th scope="row">{model.modelLabel}</th>
                    <td>{model.attemptedRunCount}</td>
                    <td>{model.successfulRunCount}</td>
                    <td>{model.omittedRunCount}</td>
                    <td>{formatMilliseconds(model.medianMs)}</td>
                    <td>{model.relativeMedian === null ? "—" : `${model.relativeMedian.toFixed(3)}×`}</td>
                    <td><Link to={modelRunsPath(model.modelId, activeCell)}>Open runs</Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </details>
      )}
    </main>
  );
}
