import { useCallback, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import type { VisualizationSpec } from "vega-embed";

import { aggregateTiers } from "../analysis/tiers";
import { filterRuns } from "../analysis/runs";
import { FilterBar } from "../components/FilterBar";
import { VegaChart } from "../components/VegaChart";
import { loadRuns } from "../data/client";
import { useDataset } from "../data/context";
import { useFilterState } from "../state/filters";
import { downloadText, runsToCsv } from "../utils/csv";
import { useMediaQuery } from "../utils/media";

function runLink(modelId: string, bandId: string, current: URLSearchParams): string {
  const next = new URLSearchParams(current);
  next.delete("model");
  next.append("model", modelId);
  next.delete("band");
  next.append("band", bandId);
  next.delete("sort");
  next.delete("page");
  const query = next.toString();
  return `/runs${query ? `?${query}` : ""}`;
}

export function TiersView() {
  const { manifest, scoreCube } = useDataset();
  const { state, params, replaceValues, replaceValue, reset } = useFilterState(manifest);
  const navigate = useNavigate();
  const [exporting, setExporting] = useState(false);
  const isNarrow = useMediaQuery("(max-width: 600px)");
  const isDark = useMediaQuery("(prefers-color-scheme: dark)");
  const summaries = useMemo(() => aggregateTiers(scoreCube, manifest, state), [manifest, scoreCube, state]);
  const segments = useMemo(() => summaries.flatMap((summary) => summary.segments), [summaries]);
  const modelLabels = useMemo(() => summaries.map((summary) => ({
    modelId: summary.modelId,
    modelLabel: summary.modelLabel,
    modelHarnessLabel: summary.modelHarnessLabel,
    modelInvocationLabel: summary.modelInvocationLabel,
  })), [summaries]);
  const visibleRuns = summaries.reduce((total, model) => total + model.runCount, 0);
  const weightedMean = visibleRuns === 0 ? null : summaries.reduce((total, model) => total + model.meanScore * model.runCount, 0) / visibleRuns;
  const modelOrder = summaries.map((summary) => summary.modelLabel);

  const spec = useMemo<VisualizationSpec>(() => ({
    $schema: "https://vega.github.io/schema/vega-lite/v6.json",
    width: "container",
    height: Math.max(220, summaries.length * (isNarrow ? 34 : 39)),
    autosize: { type: "fit-x", contains: "padding", resize: true },
    padding: { left: 4, right: 16, top: 6, bottom: 4 },
    data: { values: segments },
    encoding: {
      y: {
        field: "modelLabel", type: "nominal", sort: modelOrder,
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
        field: "startPercentage", type: "quantitative",
        scale: { domain: [0, 100] },
        axis: {
          title: "Share of scored runs",
          titleFontSize: isNarrow ? 12 : 14,
          labelFontSize: isNarrow ? 11 : 13,
          format: ".0f",
          labelExpr: "datum.label + '%'",
          grid: true,
          tickCount: 6,
        },
      },
      color: {
        field: "bandLabel", type: "nominal",
        scale: {
          domain: manifest.scoreScale.bands.map((band) => band.label),
          range: manifest.scoreScale.bands.map((band) => band.color),
        },
        legend: {
          title: null,
          orient: "top",
          direction: "horizontal",
          columns: isNarrow ? 2 : 4,
          symbolType: "square",
          symbolSize: isNarrow ? 120 : 150,
          labelFontSize: isNarrow ? 12 : 14,
        },
      },
      order: { field: "bandOrder", type: "ordinal" },
      tooltip: [
        { field: "bandLabel", title: "Tier" },
        { field: "bandDetail", title: "Score range" },
        { field: "count", title: "Runs", format: ",d" },
        { field: "percentage", title: "Share (%)", format: ".1f" },
        { field: "runCount", title: "Model sample", format: ",d" },
        { field: "meanScore", title: "Mean score", format: ".2f" },
      ],
    },
    layer: [
      {
        mark: { type: "bar", cornerRadius: 1, stroke: isDark ? "#182126" : "#ffffff", strokeWidth: 0.6 },
        encoding: { x2: { field: "endPercentage" } },
      },
      {
        transform: [{ filter: "datum.percentage >= 7" }],
        mark: { type: "text", color: "white", fontSize: isNarrow ? 11 : 13, fontWeight: 650, baseline: "middle" },
        encoding: {
          x: { field: "midpointPercentage", type: "quantitative" },
          color: { value: "#ffffff" },
          text: { field: "percentage", type: "quantitative", format: ".0f" },
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
          y: { field: "modelLabel", type: "nominal", sort: modelOrder },
          color: { value: isDark ? "#c1cbc9" : "#49535d" },
          text: { field: "modelLabel", type: "nominal" },
          tooltip: [
            { field: "modelLabel", title: "Model" },
            { field: "modelHarnessLabel", title: "Agent harness" },
            { field: "modelInvocationLabel", title: "Invocation" },
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
      legend: { labelColor: isDark ? "#edf0eb" : "#303941", labelFontSize: isNarrow ? 12 : 14, offset: 12 },
      view: { stroke: null },
    },
  }) as VisualizationSpec, [isDark, isNarrow, manifest.scoreScale.bands, modelLabels, modelOrder, segments, summaries.length]);

  const openSegment = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.modelId === "string" && typeof datum.bandId === "string") {
      navigate(runLink(datum.modelId, datum.bandId, params));
    }
  }, [navigate, params]);

  async function exportRecords(): Promise<void> {
    setExporting(true);
    try {
      const runs = await loadRuns(manifest, state.benchmarks, state.backends);
      const active = filterRuns(runs, {
        models: state.models,
        scoreBands: [],
        exactScore: null,
        validation: "all",
        benchmark: "all",
        query: "",
      });
      downloadText("llm-eval-tiered-selection.csv", runsToCsv(active), "text/csv;charset=utf-8");
    } finally {
      setExporting(false);
    }
  }

  return (
    <main id="main-content" className="page-shell">
      <header className="view-summary">
        <h1 className="sr-only">Tiered Success</h1>
        <p>Runs are grouped into the reviewed score bands. Counts, shares, and means are recomputed for the active filters.</p>
      </header>

      <FilterBar
        manifest={manifest}
        filters={state}
        onModels={(values) => replaceValues("model", values)}
        onBenchmarks={(values) => replaceValues("benchmark", values)}
        onBackends={(values) => replaceValues("backend", values)}
        onReset={reset}
        additionalActiveCount={state.sort === "weakest" ? 0 : 1}
        resultSummary={(
          <div className="filter-result-summary" aria-label="Current selection summary">
            <span><strong>{summaries.length}</strong> {summaries.length === 1 ? "model" : "models"}</span>
            <span><strong>{visibleRuns.toLocaleString()}</strong> {visibleRuns === 1 ? "run" : "runs"}</span>
            <span><strong>{weightedMean?.toFixed(2) ?? "—"}</strong> mean score</span>
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

      <section className="analysis-panel">
        <header className="panel-heading">
          <div>
            <h2>Share of runs by score tier</h2>
            <p>Select a segment to inspect its individual runs.</p>
          </div>
          <button className="secondary-button" type="button" disabled={exporting || visibleRuns === 0} onClick={() => void exportRecords()}>
            {exporting ? "Preparing…" : "Export records · CSV"}
          </button>
        </header>
        {summaries.length > 0 ? (
          <>
            <VegaChart spec={spec} ariaLabel={`Stacked score-tier chart for ${summaries.length} models and ${visibleRuns} runs`} onDatumClick={openSegment} />
            <p className="chart-footnote"><span aria-hidden="true">↳</span> Percentages use each model’s filtered sample size. Hover for counts and mean scores.</p>
          </>
        ) : (
          <div className="empty-state">
            <p className="eyebrow">No observations</p>
            <h2>This filter combination has no scored runs.</h2>
            <button className="secondary-button" type="button" onClick={reset}>Clear filters</button>
          </div>
        )}
      </section>

      {summaries.length > 0 && (
        <details className="accessible-data">
          <summary>Accessible data table</summary>
          <div className="table-scroll">
            <table>
              <caption>Tier counts and percentages for the active selection</caption>
              <thead><tr><th scope="col">Model</th><th scope="col">Runs</th><th scope="col">Mean</th>{manifest.scoreScale.bands.map((band) => <th key={band.id} scope="col">{band.label}</th>)}</tr></thead>
              <tbody>
                {summaries.map((summary) => (
                  <tr key={summary.modelId}>
                    <th scope="row">{summary.modelLabel}</th>
                    <td>{summary.runCount}</td>
                    <td>{summary.meanScore.toFixed(2)}</td>
                    {summary.segments.map((segment) => (
                      <td key={segment.bandId}>
                        <Link to={runLink(segment.modelId, segment.bandId, params)}>{segment.count} <small>({segment.percentage.toFixed(1)}%)</small></Link>
                      </td>
                    ))}
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
