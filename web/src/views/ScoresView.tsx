import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import type { VisualizationSpec } from "vega-embed";

import { summarizeModelScores } from "../analysis/scores";
import { FilterBar } from "../components/FilterBar";
import { VegaChart } from "../components/VegaChart";
import { loadRuns } from "../data/client";
import { useDataset } from "../data/context";
import type { FilterState, RunRecord } from "../data/types";
import { useFilterState } from "../state/filters";
import { downloadText, runsToCsv } from "../utils/csv";
import { useMediaQuery } from "../utils/media";

function copySharedParams(source: URLSearchParams): URLSearchParams {
  const target = new URLSearchParams();
  for (const key of ["model", "benchmark", "backend"]) {
    source.getAll(key).forEach((value) => target.append(key, value));
  }
  const sort = source.get("sort");
  if (sort && sort !== "weakest") target.set("sort", sort);
  return target;
}

function detailPath(runId: string, source: URLSearchParams): string {
  const query = copySharedParams(source);
  query.set("from", "scores");
  return `/run/${encodeURIComponent(runId)}?${query}`;
}

function runsPath(modelId: string, filters: Pick<FilterState, "benchmarks" | "backends">): string {
  const query = new URLSearchParams();
  query.append("model", modelId);
  filters.benchmarks.forEach((value) => query.append("benchmark", value));
  filters.backends.forEach((value) => query.append("backend", value));
  return `/runs?${query}`;
}

function statistic(value: number): string {
  return value.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

export function ScoresView() {
  const { manifest } = useDataset();
  const { state, params, replaceValues, replaceValue, reset } = useFilterState(manifest);
  const navigate = useNavigate();
  const [runs, setRuns] = useState<RunRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [retry, setRetry] = useState(0);
  const [exporting, setExporting] = useState(false);
  const isNarrow = useMediaQuery("(max-width: 600px)");
  const isDark = useMediaQuery("(prefers-color-scheme: dark)");
  const benchmarkKey = state.benchmarks.join("\0");
  const backendKey = state.backends.join("\0");

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    loadRuns(manifest, state.benchmarks, state.backends).then((loaded) => {
      if (active) setRuns(loaded);
    }).catch((reason: unknown) => {
      if (active) setError(reason instanceof Error ? reason : new Error(String(reason)));
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => { active = false; };
    // Stable joined keys prevent refetching when model or ordering controls change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [manifest, benchmarkKey, backendKey, retry]);

  const activeRuns = useMemo(() => {
    const selectedModels = new Set(state.models);
    return runs.filter((run) => selectedModels.size === 0 || selectedModels.has(run.modelId));
  }, [runs, state.models]);
  const summaries = useMemo(
    () => summarizeModelScores(activeRuns, manifest, state),
    [activeRuns, manifest, state],
  );
  const visibleRuns = activeRuns.length;
  const weightedMean = visibleRuns === 0
    ? null
    : activeRuns.reduce((total, run) => total + run.overallScore, 0) / visibleRuns;
  const modelOrder = summaries.map((summary) => summary.modelId);
  const chartHeight = Math.max(isNarrow ? 96 : 110, summaries.length * (isNarrow ? 38 : 44));
  const rowStep = chartHeight / Math.max(1, summaries.length);
  const paramsKey = params.toString();
  const returnQuery = useMemo(() => copySharedParams(new URLSearchParams(paramsKey)).toString(), [paramsKey]);
  const points = useMemo(() => summaries.flatMap((summary) => summary.points.map((point) => ({
    ...point,
    jitterOffset: rowStep / 2 + (point.jitter - 0.5) * (isNarrow ? 16 : 20),
    accessibleDescription: `Run ${point.runId}; ${point.modelLabel}; score ${point.score}; ${point.benchmarkLabel}; ${point.backendLabel}; repetition ${point.repetition}`,
  }))), [isNarrow, rowStep, summaries]);
  const modelLabels = useMemo(() => summaries.map((summary) => ({
    modelId: summary.modelId,
    modelLabel: summary.modelLabel,
    modelHarnessLabel: summary.modelHarnessLabel,
    modelInvocationLabel: summary.modelInvocationLabel,
    runCount: summary.runCount,
    meanScore: summary.meanScore,
  })), [summaries]);

  const spec = useMemo<VisualizationSpec>(() => ({
    $schema: "https://vega.github.io/schema/vega-lite/v6.json",
    width: "container",
    height: chartHeight,
    autosize: { type: "fit-x", contains: "padding", resize: true },
    padding: { left: 4, right: 16, top: 6, bottom: 4 },
    data: { values: points },
    encoding: {
      y: {
        field: "modelId", type: "nominal", sort: modelOrder,
        axis: {
          title: null,
          labelLimit: isNarrow ? 150 : 220,
          labelPadding: 10,
          labelFontSize: isNarrow ? 11 : 14,
          labelFontWeight: 520,
          labelOpacity: 0,
          ticks: false,
          domain: false,
        },
      },
      x: {
        field: "score", type: "quantitative",
        scale: { domain: [manifest.scoreScale.minimum, manifest.scoreScale.maximum], nice: false },
        axis: {
          title: "Overall score",
          values: Array.from(
            { length: manifest.scoreScale.maximum - manifest.scoreScale.minimum + 1 },
            (_, index) => manifest.scoreScale.minimum + index,
          ),
          titleFontSize: isNarrow ? 12 : 14,
          labelFontSize: isNarrow ? 11 : 13,
          grid: true,
        },
      },
    },
    layer: [
      {
        mark: {
          type: "boxplot",
          extent: 1.5,
          size: isNarrow ? 17 : 21,
          outliers: false,
          color: isDark ? "#8fb8f5" : "#0b5bbb",
          box: {
            fill: isDark ? "#416a98" : "#b9d3f5",
            fillOpacity: isDark ? 0.5 : 0.62,
            stroke: isDark ? "#9fc5f8" : "#0b5bbb",
            strokeWidth: 1.25,
          },
          median: { color: isDark ? "#ffffff" : "#102b49", strokeWidth: 2.1 },
          rule: { color: isDark ? "#9fc5f8" : "#0b5bbb", strokeWidth: 1.15 },
          ticks: { color: isDark ? "#9fc5f8" : "#0b5bbb", strokeWidth: 1.15 },
        },
        encoding: {
          tooltip: [
            { field: "modelLabel", title: "Model" },
            { aggregate: "max", field: "runCount", title: "Runs", format: ",d" },
            { aggregate: "max", field: "meanScore", title: "Mean", format: ".2f" },
            { aggregate: "max", field: "lowerWhisker", title: "Lower whisker", format: ".2f" },
            { aggregate: "max", field: "firstQuartile", title: "Q1", format: ".2f" },
            { aggregate: "max", field: "median", title: "Median", format: ".2f" },
            { aggregate: "max", field: "thirdQuartile", title: "Q3", format: ".2f" },
            { aggregate: "max", field: "upperWhisker", title: "Upper whisker", format: ".2f" },
            { aggregate: "max", field: "outlierCount", title: "Outliers", format: ",d" },
          ],
        },
      },
      {
        data: { values: summaries },
        mark: {
          type: "point",
          shape: "diamond",
          filled: true,
          size: isNarrow ? 60 : 82,
          color: isDark ? "#f4f8ff" : "#0b3d79",
          stroke: isDark ? "#182126" : "#ffffff",
          strokeWidth: 1.2,
        },
        encoding: {
          x: { field: "meanScore", type: "quantitative" },
          tooltip: [
            { field: "modelLabel", title: "Model" },
            { field: "runCount", title: "Runs", format: ",d" },
            { field: "meanScore", title: "Mean", format: ".2f" },
            { field: "lowerWhisker", title: "Lower whisker", format: ".2f" },
            { field: "firstQuartile", title: "Q1", format: ".2f" },
            { field: "median", title: "Median", format: ".2f" },
            { field: "thirdQuartile", title: "Q3", format: ".2f" },
            { field: "upperWhisker", title: "Upper whisker", format: ".2f" },
            { field: "outlierCount", title: "Outliers", format: ",d" },
          ],
        },
      },
      {
        mark: {
          type: "circle",
          filled: true,
          size: isNarrow ? 34 : 48,
          opacity: isDark ? 0.72 : 0.64,
          stroke: isDark ? "#182126" : "#ffffff",
          strokeWidth: 0.7,
          cursor: "pointer",
        },
        encoding: {
          yOffset: {
            field: "jitterOffset", type: "quantitative", scale: null,
          },
          color: {
            field: "scoreBandLabel", type: "nominal",
            scale: {
              domain: manifest.scoreScale.bands.map((band) => band.label),
              range: manifest.scoreScale.bands.map((band) => band.color),
            },
            legend: {
              title: null,
              orient: "top",
              direction: "horizontal",
              columns: isNarrow ? 2 : 4,
              symbolType: "circle",
              symbolSize: isNarrow ? 90 : 110,
              labelFontSize: isNarrow ? 12 : 14,
            },
          },
          description: { field: "accessibleDescription", type: "nominal" },
          key: { field: "runId", type: "nominal" },
          tooltip: [
            { field: "runId", title: "Run" },
            { field: "modelLabel", title: "Model" },
            { field: "benchmarkLabel", title: "Benchmark" },
            { field: "backendLabel", title: "Backend" },
            { field: "repetition", title: "Repetition", format: "d" },
            { field: "score", title: "Score", format: "d" },
            { field: "scoreBandLabel", title: "Tier" },
            { field: "isOutlier", title: "Tukey outlier" },
          ],
        },
      },
      {
        data: { values: modelLabels },
        mark: {
          type: "text",
          align: "right",
          baseline: "middle",
          dx: -10,
          color: isDark ? "#c1cbc9" : "#49535d",
          cursor: "help",
          clip: false,
          fontSize: isNarrow ? 11 : 14,
          fontWeight: 520,
        },
        encoding: {
          x: { value: 0 },
          y: { field: "modelId", type: "nominal", sort: modelOrder },
          color: { value: isDark ? "#c1cbc9" : "#49535d" },
          text: { field: "modelLabel", type: "nominal" },
          tooltip: [
            { field: "modelLabel", title: "Model" },
            { field: "modelHarnessLabel", title: "Agent harness" },
            { field: "modelInvocationLabel", title: "Invocation" },
            { field: "runCount", title: "Runs", format: ",d" },
            { field: "meanScore", title: "Mean", format: ".2f" },
          ],
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
      legend: { labelColor: isDark ? "#edf0eb" : "#303941", offset: 12 },
      view: { stroke: null },
    },
  }) as VisualizationSpec, [chartHeight, isDark, isNarrow, manifest.scoreScale, modelLabels, modelOrder, points, summaries]);

  const openPoint = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.runId === "string") {
      navigate(detailPath(datum.runId, new URLSearchParams(returnQuery)));
    }
  }, [navigate, returnQuery]);

  async function exportRecords(): Promise<void> {
    setExporting(true);
    try {
      downloadText("llm-eval-model-scores.csv", runsToCsv(activeRuns), "text/csv;charset=utf-8");
    } finally {
      setExporting(false);
    }
  }

  const filterState = { ...state, scoreBands: [], outcome: "all" as const };

  return (
    <main id="main-content" className="page-shell">
      <header className="view-summary">
        <h1 className="sr-only">Model scores</h1>
        <p>Tukey box plots summarize overall scores by model; jittered points show individual runs. Statistics are recomputed for the active filters.</p>
      </header>

      <FilterBar
        manifest={manifest}
        filters={filterState}
        onModels={(values) => replaceValues("model", values)}
        onBenchmarks={(values) => replaceValues("benchmark", values)}
        onBackends={(values) => replaceValues("backend", values)}
        onReset={reset}
        additionalActiveCount={state.sort === "weakest" ? 0 : 1}
        resultSummary={(
          <div className="filter-result-summary" aria-label="Current score selection summary">
            <span><strong>{loading ? "…" : summaries.length}</strong> {summaries.length === 1 ? "model" : "models"}</span>
            <span><strong>{loading ? "…" : visibleRuns.toLocaleString()}</strong> {visibleRuns === 1 ? "run" : "runs"}</span>
            <span><strong>{loading ? "…" : weightedMean?.toFixed(2) ?? "—"}</strong> mean score</span>
          </div>
        )}
      >
        <label className="inline-select">
          <span>Order</span>
          <select value={state.sort} onChange={(event) => replaceValue("sort", event.target.value, "weakest")}>
            <option value="weakest">Weakest to best</option>
            <option value="strongest">Best to weakest</option>
            <option value="alphabetical">Alphabetical</option>
          </select>
        </label>
      </FilterBar>

      <section className="analysis-panel score-analysis">
        <header className="panel-heading">
          <div>
            <h2>Per-model score distributions</h2>
            <p>Boxes use 1.5 × IQR whiskers. Select a point to inspect that run.</p>
          </div>
          <button className="secondary-button" type="button" disabled={exporting || loading || visibleRuns === 0} onClick={() => void exportRecords()}>
            {exporting ? "Preparing…" : "Export records · CSV"}
          </button>
        </header>

        {loading ? (
          <div className="analysis-loading" aria-live="polite"><i /><i /><i /><span>Loading individual score records…</span></div>
        ) : error ? (
          <div className="empty-state">
            <p className="eyebrow">Data error</p>
            <h2>The score observations could not be loaded.</h2>
            <p>{error.message}</p>
            <button className="secondary-button" type="button" onClick={() => setRetry((value) => value + 1)}>Try again</button>
          </div>
        ) : summaries.length > 0 ? (
          <>
            <VegaChart
              spec={spec}
              ariaLabel={`Score distribution chart for ${summaries.length} models and ${visibleRuns} individual runs`}
              onDatumClick={openPoint}
              interactiveMarkSelector='[aria-roledescription="circle"]'
            />
            <p className="chart-footnote"><span aria-hidden="true">◆</span> Diamond: filtered mean. Points are individual runs; color labels the reviewed score tier.</p>
          </>
        ) : (
          <div className="empty-state">
            <p className="eyebrow">No observations</p>
            <h2>This filter combination has no scored runs.</h2>
            <button className="secondary-button" type="button" onClick={reset}>Clear filters</button>
          </div>
        )}
      </section>

      {!loading && !error && summaries.length > 0 && (
        <details className="accessible-data">
          <summary>Accessible statistics table</summary>
          <div className="table-scroll">
            <table>
              <caption>Box-plot statistics for the active score selection</caption>
              <thead><tr><th scope="col">Model</th><th scope="col">Runs</th><th scope="col">Mean</th><th scope="col">Lower whisker</th><th scope="col">Q1</th><th scope="col">Median</th><th scope="col">Q3</th><th scope="col">Upper whisker</th><th scope="col">Outliers</th><th scope="col">Records</th></tr></thead>
              <tbody>
                {summaries.map((summary) => (
                  <tr key={summary.modelId}>
                    <th scope="row">{summary.modelLabel}</th>
                    <td>{summary.runCount}</td>
                    <td>{statistic(summary.meanScore)}</td>
                    <td>{statistic(summary.lowerWhisker)}</td>
                    <td>{statistic(summary.firstQuartile)}</td>
                    <td>{statistic(summary.median)}</td>
                    <td>{statistic(summary.thirdQuartile)}</td>
                    <td>{statistic(summary.upperWhisker)}</td>
                    <td>{summary.outlierCount}</td>
                    <td><Link to={runsPath(summary.modelId, state)}>Open runs</Link></td>
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
