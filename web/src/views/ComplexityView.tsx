import { useCallback, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import type { VisualizationSpec } from "vega-embed";

import { analyzeComplexity, type ComplexityCategorySummary } from "../analysis/complexity";
import { filterRuns } from "../analysis/runs";
import { FilterBar } from "../components/FilterBar";
import { VegaChart } from "../components/VegaChart";
import { loadRuns } from "../data/client";
import { useDataset } from "../data/context";
import type { FilterState } from "../data/types";
import { useFilterState } from "../state/filters";
import { downloadText, runsToCsv } from "../utils/csv";
import { useMediaQuery } from "../utils/media";

const densityGroupFields = [
  "categoryType", "categoryId", "categoryLabel", "categoryKey", "runCount", "meanScore",
  "firstQuartile", "median", "thirdQuartile", "grandMean", "accessibleDescription",
];

function statistic(value: number): string {
  return value.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

function runsPath(
  categoryType: "benchmark" | "backend",
  categoryId: string,
  filters: Pick<FilterState, "models" | "benchmarks" | "backends">,
  current: URLSearchParams,
): string {
  const query = new URLSearchParams();
  for (const key of ["model", "model-set"]) {
    current.getAll(key).forEach((value) => query.append(key, value));
  }
  (categoryType === "benchmark" ? [categoryId] : filters.benchmarks)
    .forEach((value) => query.append("benchmark", value));
  (categoryType === "backend" ? [categoryId] : filters.backends)
    .forEach((value) => query.append("backend", value));
  return `/runs?${query}`;
}

function summaryTooltip() {
  return [
    { field: "categoryLabel", title: "Category" },
    { field: "runCount", title: "Runs", format: ",d" },
    { field: "meanScore", title: "Mean", format: ".2f" },
    { field: "firstQuartile", title: "Q1", format: ".2f" },
    { field: "median", title: "Median", format: ".2f" },
    { field: "thirdQuartile", title: "Q3", format: ".2f" },
    { field: "grandMean", title: "Grand mean", format: ".2f" },
  ];
}

export function ComplexityView() {
  const { manifest, scoreCube } = useDataset();
  const { state, params, replaceValues, reset } = useFilterState(manifest);
  const navigate = useNavigate();
  const [exporting, setExporting] = useState(false);
  const isNarrow = useMediaQuery("(max-width: 600px)");
  const isCompact = useMediaQuery("(max-width: 1050px)");
  const isDark = useMediaQuery("(prefers-color-scheme: dark)");
  const analysis = useMemo(() => analyzeComplexity(scoreCube, manifest, state), [manifest, scoreCube, state]);
  const scoreDomain = [manifest.scoreScale.minimum, manifest.scoreScale.maximum];
  const scoreTicks = Array.from(
    { length: manifest.scoreScale.maximum - manifest.scoreScale.minimum + 1 },
    (_, index) => manifest.scoreScale.minimum + index,
  );
  const densityBandwidth = Math.max((manifest.scoreScale.maximum - manifest.scoreScale.minimum) / 20, 0.01);
  const benchmarkOrder = analysis.benchmarkSummaries.map((summary) => summary.categoryKey);
  const backendOrder = analysis.backendSummaries.map((summary) => summary.categoryKey);
  const benchmarkWidth = isNarrow ? 150 : isCompact ? 585 : 705;
  const benchmarkRowHeight = isNarrow ? 38 : 44;
  const targetWidth = isNarrow ? 52 : isCompact ? 70 : 76;
  const targetHeight = isNarrow ? 270 : 390;
  const densityFill = isDark ? "#416a98" : "#a9c7e2";
  const densityStroke = isDark ? "#9fc5f8" : "#527b9b";
  const statisticStroke = isDark ? "#d7e2ed" : "#3d4d57";
  const meanFill = isDark ? "#f4f8ff" : "#003f91";
  const meanStroke = isDark ? "#182126" : "#ffffff";
  const grandMeanStroke = isDark ? "#aab8ba" : "#78858b";
  const chartConfig = {
    background: isDark ? "#182126" : "#ffffff",
    font: "Roboto Condensed Variable, Roboto Condensed, Arial Narrow, sans-serif",
    axis: {
      labelColor: isDark ? "#c1cbc9" : "#49535d",
      titleColor: isDark ? "#c1cbc9" : "#49535d",
      gridColor: isDark ? "#334147" : "#dfe2e1",
      gridOpacity: 0.72,
    },
    header: {
      labelColor: isDark ? "#c1cbc9" : "#3f4c55",
      labelFont: "Roboto Condensed Variable, Roboto Condensed, Arial Narrow, sans-serif",
      title: null,
    },
    view: { stroke: null },
  };

  const benchmarkSpec = useMemo<VisualizationSpec>(() => ({
    $schema: "https://vega.github.io/schema/vega-lite/v6.json",
    data: { values: analysis.benchmarkObservations },
    facet: {
      row: {
        field: "categoryKey", type: "nominal", sort: benchmarkOrder,
        header: {
          title: null,
          labelAngle: 0,
          labelAlign: "left",
          labelBaseline: "middle",
          labelFontSize: isNarrow ? 11 : 14,
          labelFontWeight: 540,
          labelLimit: isNarrow ? 105 : 175,
          labelPadding: 8,
        },
      },
    },
    spacing: 0,
    spec: {
      width: benchmarkWidth,
      height: benchmarkRowHeight,
      layer: [
        {
          transform: [
            {
              density: "score", groupby: densityGroupFields, extent: scoreDomain,
              bandwidth: densityBandwidth, steps: 81, as: ["scoreValue", "density"],
            },
            { calculate: "-datum.density", as: "negativeDensity" },
          ],
          mark: {
            type: "area", orient: "horizontal", interpolate: "monotone",
            fill: densityFill, fillOpacity: isDark ? 0.66 : 0.78,
            stroke: densityStroke, strokeWidth: 1.1, cursor: "pointer",
          },
          encoding: {
            x: {
              field: "scoreValue", type: "quantitative", scale: { domain: scoreDomain, nice: false },
              axis: {
                title: "Overall score", values: scoreTicks,
                format: "d", labelFlush: true, labelFlushOffset: 2,
                titleFontSize: isNarrow ? 12 : 14, labelFontSize: isNarrow ? 11 : 13, grid: true,
              },
            },
            y: { field: "density", type: "quantitative", axis: null },
            y2: { field: "negativeDensity" },
            description: { field: "accessibleDescription", type: "nominal" },
            tooltip: summaryTooltip(),
          },
        },
        {
          mark: { type: "rule", color: grandMeanStroke, strokeDash: [7, 5], strokeWidth: 1.35 },
          encoding: {
            x: { aggregate: "max", field: "grandMean", type: "quantitative" },
            y: { value: 0 }, y2: { value: benchmarkRowHeight },
            tooltip: [{ aggregate: "max", field: "grandMean", title: "Grand mean", format: ".2f" }],
          },
        },
        {
          mark: { type: "rule", color: statisticStroke, strokeWidth: 1.35 },
          encoding: {
            x: { aggregate: "max", field: "median", type: "quantitative" },
            y: { value: 4 }, y2: { value: benchmarkRowHeight - 4 },
          },
        },
        {
          mark: {
            type: "point", shape: "diamond", filled: true, size: isNarrow ? 72 : 96,
            color: meanFill, stroke: meanStroke, strokeWidth: 1.1, cursor: "pointer",
          },
          encoding: {
            x: { aggregate: "max", field: "meanScore", type: "quantitative" },
            y: { value: benchmarkRowHeight / 2 },
            detail: { field: "categoryId", type: "nominal" },
            key: { field: "categoryId", type: "nominal" },
            description: { field: "accessibleDescription", type: "nominal" },
            tooltip: summaryTooltip(),
          },
        },
      ],
    },
    resolve: { scale: { y: "independent" } },
    config: chartConfig,
  }) as VisualizationSpec, [
    analysis.benchmarkObservations, benchmarkOrder, benchmarkRowHeight, benchmarkWidth,
    chartConfig, densityBandwidth, densityFill, densityStroke, grandMeanStroke, isDark, isNarrow,
    meanFill, meanStroke, scoreDomain, scoreTicks, statisticStroke,
  ]);

  const targetSpec = useMemo<VisualizationSpec>(() => ({
    $schema: "https://vega.github.io/schema/vega-lite/v6.json",
    data: { values: analysis.backendObservations },
    facet: {
      column: {
        field: "categoryKey", type: "nominal", sort: backendOrder,
        header: {
          title: null,
          orient: "bottom",
          labelAngle: 0,
          labelFontSize: isNarrow ? 11 : 14,
          labelFontWeight: 540,
          labelLimit: targetWidth + 12,
          labelPadding: 18,
        },
      },
    },
    spacing: isNarrow ? 5 : 8,
    spec: {
      width: targetWidth,
      height: targetHeight,
      layer: [
        {
          transform: [
            {
              density: "score", groupby: densityGroupFields, extent: scoreDomain,
              bandwidth: densityBandwidth, steps: 81, as: ["scoreValue", "density"],
            },
            { calculate: "-datum.density", as: "negativeDensity" },
          ],
          mark: {
            type: "area", orient: "vertical", interpolate: "monotone",
            fill: densityFill, fillOpacity: isDark ? 0.66 : 0.78,
            stroke: densityStroke, strokeWidth: 1.1, cursor: "pointer",
          },
          encoding: {
            y: {
              field: "scoreValue", type: "quantitative", scale: { domain: scoreDomain, nice: false },
              axis: {
                title: "Overall score", values: scoreTicks,
                titleFontSize: isNarrow ? 12 : 14, labelFontSize: isNarrow ? 11 : 13, grid: true,
              },
            },
            x: { field: "density", type: "quantitative", axis: null },
            x2: { field: "negativeDensity" },
            description: { field: "accessibleDescription", type: "nominal" },
            tooltip: summaryTooltip(),
          },
        },
        {
          mark: { type: "rule", color: grandMeanStroke, strokeDash: [7, 5], strokeWidth: 1.35 },
          encoding: {
            y: { aggregate: "max", field: "grandMean", type: "quantitative" },
            x: { value: 0 }, x2: { value: targetWidth },
            tooltip: [{ aggregate: "max", field: "grandMean", title: "Grand mean", format: ".2f" }],
          },
        },
        {
          mark: {
            type: "point", shape: "diamond", filled: true, size: isNarrow ? 92 : 118,
            color: meanFill, stroke: meanStroke, strokeWidth: 1.1, cursor: "pointer",
          },
          encoding: {
            y: { aggregate: "max", field: "meanScore", type: "quantitative" },
            x: { value: targetWidth / 2 },
            detail: { field: "categoryId", type: "nominal" },
            key: { field: "categoryId", type: "nominal" },
            description: { field: "accessibleDescription", type: "nominal" },
            tooltip: summaryTooltip(),
          },
        },
        {
          mark: {
            type: "text", align: "center", baseline: "bottom", dy: -9,
            color: isDark ? "#edf0eb" : "#182127", fontSize: isNarrow ? 11 : 14, fontWeight: 690,
          },
          encoding: {
            y: { aggregate: "max", field: "meanScore", type: "quantitative" },
            x: { value: targetWidth / 2 },
            text: { aggregate: "max", field: "meanScore", type: "quantitative", format: ".2f" },
          },
        },
      ],
    },
    resolve: { scale: { x: "independent" } },
    config: chartConfig,
  }) as VisualizationSpec, [
    analysis.backendObservations, backendOrder, chartConfig, densityBandwidth, densityFill, densityStroke,
    grandMeanStroke, isDark, isNarrow, meanFill, meanStroke, scoreDomain, scoreTicks,
    targetHeight, targetWidth,
  ]);

  const openBenchmark = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.categoryId === "string") navigate(runsPath("benchmark", datum.categoryId, state, params));
  }, [navigate, params, state]);

  const openTarget = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.categoryId === "string") navigate(runsPath("backend", datum.categoryId, state, params));
  }, [navigate, params, state]);

  async function exportRecords(): Promise<void> {
    setExporting(true);
    try {
      const runs = await loadRuns(manifest, state.benchmarks, state.backends);
      const active = filterRuns(runs, {
        models: state.models,
        scoreBands: [], exactScore: null, validation: "all", benchmark: "all", query: "",
      });
      downloadText("llm-eval-complexity-selection.csv", runsToCsv(active), "text/csv;charset=utf-8");
    } finally {
      setExporting(false);
    }
  }

  const renderTable = (caption: string, label: string, summaries: ComplexityCategorySummary[]) => (
    <div className="table-scroll">
      <table>
        <caption>{caption}</caption>
        <thead><tr><th scope="col">{label}</th><th scope="col">Runs</th><th scope="col">Mean</th><th scope="col">Q1</th><th scope="col">Median</th><th scope="col">Q3</th><th scope="col">Records</th></tr></thead>
        <tbody>
          {summaries.map((summary) => (
            <tr key={summary.categoryId}>
              <th scope="row">{summary.categoryLabel}</th>
              <td>{summary.runCount}</td>
              <td>{statistic(summary.meanScore)}</td>
              <td>{statistic(summary.firstQuartile)}</td>
              <td>{statistic(summary.median)}</td>
              <td>{statistic(summary.thirdQuartile)}</td>
              <td><Link to={runsPath(summary.categoryType, summary.categoryId, state, params)}>Open runs</Link></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );

  return (
    <main id="main-content" className="page-shell">
      <header className="view-summary">
        <h1 className="sr-only">Benchmark / Target complexity</h1>
        <p>Score distributions are grouped by benchmark and parallelization target. Quartiles, means, and the grand mean are recomputed for the active filters.</p>
      </header>

      <FilterBar
        manifest={manifest}
        filters={{ ...state, scoreBands: [], outcome: "all" }}
        onModels={(values) => replaceValues("model", values)}
        onBenchmarks={(values) => replaceValues("benchmark", values)}
        onBackends={(values) => replaceValues("backend", values)}
        onReset={reset}
        resultSummary={(
          <div className="filter-result-summary" aria-label="Current complexity selection summary">
            <span><strong>{analysis.modelCount}</strong> {analysis.modelCount === 1 ? "model" : "models"}</span>
            <span><strong>{analysis.runCount.toLocaleString()}</strong> {analysis.runCount === 1 ? "run" : "runs"}</span>
            <span><strong>{analysis.grandMean?.toFixed(2) ?? "—"}</strong> grand mean</span>
          </div>
        )}
      />

      {analysis.runCount > 0 ? (
        <>
          <div className="complexity-grid">
            <section className="analysis-panel benchmark-complexity">
              <header className="panel-heading">
                <div>
                  <h2>Benchmark complexity</h2>
                  <p>Benchmarks are ordered from highest to lowest filtered mean score.</p>
                </div>
                <button className="secondary-button" type="button" disabled={exporting} onClick={() => void exportRecords()}>
                  {exporting ? "Preparing…" : "Export active records · CSV"}
                </button>
              </header>
              <VegaChart
                spec={benchmarkSpec}
                ariaLabel={`Benchmark complexity violin chart for ${analysis.benchmarkSummaries.length} benchmarks and ${analysis.runCount} runs`}
                onDatumClick={openBenchmark}
                interactiveMarkSelector='[aria-roledescription="area"], [aria-roledescription="point"]'
              />
              <p className="chart-footnote">The diamond marks the mean; the solid rule marks the median; the dashed rule marks the active grand mean. Select a violin or mean to open its runs.</p>
            </section>

            <section className="analysis-panel target-complexity">
              <header className="panel-heading">
                <div>
                  <h2>Target complexity</h2>
                  <p>Parallelization targets use the same active observations and score scale.</p>
                </div>
              </header>
              <VegaChart
                spec={targetSpec}
                ariaLabel={`Target complexity violin chart for ${analysis.backendSummaries.length} targets and ${analysis.runCount} runs`}
                onDatumClick={openTarget}
                interactiveMarkSelector='[aria-roledescription="area"], [aria-roledescription="point"]'
              />
              <p className="chart-footnote">Labels show the filtered mean. Violin width represents kernel density on the manifest-defined score domain.</p>
            </section>
          </div>

          <details className="accessible-data">
            <summary>Accessible complexity statistics</summary>
            {renderTable("Benchmark score-distribution statistics for the active selection", "Benchmark", analysis.benchmarkSummaries)}
            {renderTable("Target score-distribution statistics for the active selection", "Target", analysis.backendSummaries)}
          </details>
        </>
      ) : (
        <div className="empty-state analysis-panel">
          <p className="eyebrow">No observations</p>
          <h2>This filter combination has no scored runs.</h2>
          <button className="secondary-button" type="button" onClick={reset}>Clear filters</button>
        </div>
      )}
    </main>
  );
}
