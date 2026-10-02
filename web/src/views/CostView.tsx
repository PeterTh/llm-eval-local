import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import type { VisualizationSpec } from "vega-embed";

import { adaptiveScoreDomain, analyzeCost, costDomain, type CostAnalysis, type CostModelSummary } from "../analysis/cost";
import { FilterBar } from "../components/FilterBar";
import { HighlightActions, HighlightCheckbox, highlightColor } from "../components/HighlightActions";
import { ParetoLegend } from "../components/ParetoLegend";
import { scatterLabels } from "../components/scatterLabels";
import { VegaChart } from "../components/VegaChart";
import { loadCostDataset } from "../data/client";
import { useDataset } from "../data/context";
import type { CostDataset, FilterState } from "../data/types";
import { useFilterState } from "../state/filters";
import { copyHighlights, modelHighlightId, useHighlightState } from "../state/highlights";
import { costSummariesToCsv, downloadText } from "../utils/csv";
import { formatCount, formatScore, formatUsd, formatUsdPerMillion } from "../utils/format";
import { useMediaQuery } from "../utils/media";

const EMPTY_ANALYSIS: CostAnalysis = {
  models: [],
  plottedModels: [],
  paretoModelIds: [],
  scoreRunCount: 0,
  costRunCount: 0,
  unavailableCostRunCount: 0,
  unpricedModelCount: 0,
};

const LIGHT_POINT_COLORS = ["#004aad", "#3c6fa8", "#655f9b", "#28786d", "#8a5b42", "#6f6d31", "#526f91"];
const DARK_POINT_COLORS = ["#8fb8f5", "#74a7dc", "#aaa0e1", "#69b9ab", "#d5a080", "#b8b36a", "#91afd0"];

function compactChartLabel(label: string): string {
  if (label.length <= 19) return label;
  return `${label.slice(0, 11)}…${label.slice(-7)}`;
}

function runsPath(modelId: string, filters: Pick<FilterState, "benchmarks" | "backends">, current: URLSearchParams): string {
  const query = copyHighlights(current);
  query.append("model", modelId);
  filters.benchmarks.forEach((benchmark) => query.append("benchmark", benchmark));
  filters.backends.forEach((backend) => query.append("backend", backend));
  return `/runs?${query}`;
}

function pricingLinks(summary: CostModelSummary) {
  const links = [
    summary.pricingSourceUrl ? { label: "Pricing source", url: summary.pricingSourceUrl } : null,
    summary.pricingEndpointUrl ? { label: "Endpoint record", url: summary.pricingEndpointUrl } : null,
    summary.secondaryPricingSourceUrl ? { label: "Secondary source", url: summary.secondaryPricingSourceUrl } : null,
  ].filter((link): link is { label: string; url: string } => link !== null);
  if (links.length === 0) return <span>Unavailable</span>;
  return links.map((link, index) => (
    <span key={link.url}>{index > 0 ? " · " : ""}<a href={link.url} target="_blank" rel="noreferrer">{link.label}</a></span>
  ));
}

export function CostView() {
  const { manifest } = useDataset();
  const { state, params, replaceValues, replaceValue, reset } = useFilterState(manifest);
  const navigate = useNavigate();
  const [dataset, setDataset] = useState<CostDataset | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [retry, setRetry] = useState(0);
  const [exporting, setExporting] = useState(false);
  const isNarrow = useMediaQuery("(max-width: 600px)");
  const isDark = useMediaQuery("(prefers-color-scheme: dark)");

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    loadCostDataset(manifest).then((loaded) => {
      if (active) setDataset(loaded);
    }).catch((reason: unknown) => {
      if (active) setError(reason instanceof Error ? reason : new Error(String(reason)));
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => { active = false; };
  }, [manifest, retry]);

  const analysis = useMemo(
    () => dataset ? analyzeCost(dataset, manifest, state) : EMPTY_ANALYSIS,
    [dataset, manifest, state],
  );
  const scoreDomain = adaptiveScoreDomain(
    analysis.plottedModels.map((model) => model.meanScore),
    manifest.scoreScale.minimum,
    manifest.scoreScale.maximum,
  );
  const paretoModels = useMemo(() => new Set(analysis.paretoModelIds), [analysis.paretoModelIds]);
  const highlights = useHighlightState("modelIds", analysis.plottedModels.map((model) => model.modelId));
  const plottedModels = new Set(analysis.plottedModels.map((model) => model.modelId));
  const xDomain = costDomain(
    analysis.plottedModels.flatMap((model) => model.meanEstimatedCostUsd === null ? [] : [model.meanEstimatedCostUsd]),
    state.scale,
  );
  const pointColors = isDark ? DARK_POINT_COLORS : LIGHT_POINT_COLORS;
  const chartPoints = useMemo(() => analysis.plottedModels.map((model) => ({
    ...model,
    isPareto: paretoModels.has(model.modelId),
    paretoLabel: paretoModels.has(model.modelId) ? "Yes" : "No",
    isHighlighted: highlights.selected.has(model.modelId),
    highlightLabel: highlights.selected.has(model.modelId) ? "Yes" : "No",
    accessibleDescription: `${model.accessibleDescription}; Pareto front: ${paretoModels.has(model.modelId) ? "Yes" : "No"}; Highlighted: ${highlights.selected.has(model.modelId) ? "Yes" : "No"}`,
    pointColor: pointColors[model.styleIndex]!,
    pointSize: Math.round((isNarrow ? 115 : 145) * (model.pointShape.startsWith("triangle") ? 1.35 : model.pointShape === "diamond" ? 1.2 : 1)),
    pointLabel: isNarrow ? compactChartLabel(model.modelLabel) : model.modelLabel,
    pricingProfileLabel: model.pricingProfileId ?? "Unavailable",
    pricingProviderLabel: model.pricingProvider ?? "Unavailable",
    pricingProviderTagLabel: model.pricingProviderTag ?? "Unavailable",
    pricingQuantizationLabel: model.pricingQuantization ?? "Unavailable",
    pricingDateLabel: model.pricingAsOf ?? "Unavailable",
    pricingMatchLabel: model.pricingMatchNote ?? "Unavailable",
  })), [analysis.plottedModels, paretoModels, highlights.selected, pointColors, isNarrow]);
  const chartHeight = isNarrow
    ? Math.max(480, chartPoints.length * (chartPoints.length > 20 ? 55 : 42))
    : Math.max(400, chartPoints.length * (chartPoints.length > 20 ? 42 : 38));
  const xTitle = state.scale === "log"
    ? "Estimated API cost per run (USD, log scale)"
    : "Estimated API cost per run (USD)";
  const chartSpec = useMemo<VisualizationSpec>(() => ({
    $schema: "https://vega.github.io/schema/vega/v6.json",
    description: `Mean overall score versus estimated API cost for ${chartPoints.length} models.`,
    width: 600,
    height: chartHeight,
    // VegaChart refits on container resize; refitting on hover can oscillate with label placement.
    autosize: { type: "fit", contains: "padding" },
    padding: { left: 8, right: 8, top: 12, bottom: 6 },
    data: [
      { name: "cost_values", values: chartPoints },
      { name: "cost_highlights", source: "cost_values", transform: [{ type: "filter", expr: "datum.isHighlighted" }] },
      {
        name: "cost_pareto", source: "cost_values", transform: [
          { type: "filter", expr: "datum.isPareto" },
          { type: "aggregate", groupby: ["meanEstimatedCostUsd", "meanScore"] },
          { type: "collect", sort: { field: "meanEstimatedCostUsd", order: "ascending" } },
        ],
      },
    ],
    scales: [
      {
        name: "cost_x",
        type: state.scale,
        domain: xDomain,
        range: "width",
        nice: false,
        zero: state.scale === "linear",
      },
      {
        name: "score_y",
        type: "linear",
        domain: scoreDomain,
        range: "height",
        nice: false,
        zero: false,
      },
    ],
    axes: [
      {
        orient: "bottom",
        scale: "cost_x",
        title: xTitle,
        grid: true,
        tickCount: isNarrow ? 4 : 7,
        labelExpr: "'$' + (datum.value < 0.1 ? format(datum.value, '.3~f') : format(datum.value, '.2~f'))",
        labelFontSize: isNarrow ? 12 : 14,
        titleFontSize: isNarrow ? 13 : 15,
        titlePadding: 10,
      },
      {
        orient: "left",
        scale: "score_y",
        title: "Mean overall score",
        grid: true,
        tickCount: isNarrow ? 5 : 7,
        format: ".2~f",
        labelFontSize: isNarrow ? 12 : 14,
        titleFontSize: isNarrow ? 13 : 15,
        titlePadding: 10,
      },
    ],
    marks: [
      {
        name: "cost_pareto_line", type: "line", from: { data: "cost_pareto" }, interactive: false, aria: false,
        encode: { update: {
          x: { scale: "cost_x", field: "meanEstimatedCostUsd" }, y: { scale: "score_y", field: "meanScore" },
          defined: { signal: "length(data('cost_pareto')) > 1" },
          stroke: { value: isDark ? "#edf0eb" : "#303941" }, strokeWidth: { value: 1.5 },
          strokeDash: { value: [6, 4] }, strokeOpacity: { value: 0.7 }, interpolate: { value: "linear" },
        } },
      },
      {
        name: "cost_highlight_halos", type: "symbol", from: { data: "cost_highlights" }, interactive: false, aria: false,
        encode: { update: {
          x: { scale: "cost_x", field: "meanEstimatedCostUsd" }, y: { scale: "score_y", field: "meanScore" },
          // Triangle edges sit closer to the origin and need more room around the Pareto stroke.
          shape: { field: "pointShape" }, size: { signal: "pow(sqrt(datum.pointSize) + (indexof(datum.pointShape, 'triangle') === 0 ? 16 : 8), 2)" },
          fill: { value: null }, stroke: { value: highlightColor(isDark) }, strokeWidth: { value: 2 },
        } },
      },
      {
        name: "cost_points",
        type: "symbol",
        from: { data: "cost_values" },
        encode: {
          update: {
            x: { scale: "cost_x", field: "meanEstimatedCostUsd" },
            y: { scale: "score_y", field: "meanScore" },
            shape: { field: "pointShape" },
            size: { field: "pointSize" },
            fill: { field: "pointColor" },
            fillOpacity: { value: 0.88 },
            stroke: [
              { test: "datum.isPareto", value: isDark ? "#edf0eb" : "#303941" },
              { value: isDark ? "#182126" : "#ffffff" },
            ],
            strokeWidth: { signal: "datum.isPareto ? 2.5 : 1.3" },
            cursor: { value: "pointer" },
            description: { field: "accessibleDescription" },
            tooltip: {
              signal: "{'Model': datum.modelLabel, 'Mean score': datum.scoreLabel, 'Estimated mean cost': datum.costLabel, 'Pareto front': datum.paretoLabel, 'Highlighted': datum.highlightLabel, 'Runs': datum.runCountsLabel, 'Mean tokens': datum.tokenSummaryLabel, 'Rates (USD/M tokens)': datum.rateSummaryLabel, 'Pricing profile': datum.pricingProfileLabel, 'Provider': datum.providerSummaryLabel, 'Quantization': datum.pricingQuantizationLabel, 'Pricing date': datum.pricingDateLabel, 'Sources': datum.sourceAvailabilityLabel}",
            },
          },
        },
      },
      ...scatterLabels({
        name: "cost_labels", points: "cost_points", font: "Roboto Condensed Variable, Roboto Condensed, Arial Narrow, sans-serif",
        fontSize: isNarrow ? 12 : 14, color: isDark ? "#edf0eb" : "#303941",
        guideColor: isDark ? "#91afd0" : "#526f91", padding: isNarrow ? 32 : 4,
      }),
    ],
    config: {
      background: isDark ? "#182126" : "#ffffff",
      font: "Roboto Condensed Variable, Roboto Condensed, Arial Narrow, sans-serif",
      axis: {
        labelColor: isDark ? "#c1cbc9" : "#49535d",
        titleColor: isDark ? "#c1cbc9" : "#49535d",
        domainColor: isDark ? "#4a5b61" : "#bdc5c3",
        tickColor: isDark ? "#4a5b61" : "#bdc5c3",
        gridColor: isDark ? "#334147" : "#dfe2e1",
        gridOpacity: 0.75,
      },
    },
  }) as VisualizationSpec, [chartHeight, chartPoints, isDark, isNarrow, scoreDomain, state.scale, xDomain, xTitle]);

  const openPoint = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.modelId === "string") navigate(runsPath(datum.modelId, state, params));
  }, [navigate, state, params]);

  function exportRecords(): void {
    setExporting(true);
    try {
      downloadText("llm-eval-score-cost.csv", costSummariesToCsv(analysis.models), "text/csv;charset=utf-8");
    } finally {
      setExporting(false);
    }
  }

  const filterState = { ...state, scoreBands: [], outcome: "all" as const };
  const additionalActiveCount = state.scale === "log" ? 0 : 1;

  return (
    <main id="main-content" className="page-shell">
      <header className="view-summary">
        <h1 className="sr-only">Cost Efficiency</h1>
        <p>Mean overall score is compared with estimated mean API cost per run for each model in the active subset.</p>
      </header>

      <FilterBar
        manifest={manifest}
        filters={filterState}
        onModels={(values) => replaceValues("model", values)}
        onBenchmarks={(values) => replaceValues("benchmark", values)}
        onBackends={(values) => replaceValues("backend", values)}
        onReset={reset}
        additionalActiveCount={additionalActiveCount}
        resultSummary={(
          <div className="filter-result-summary" aria-label="Current cost efficiency selection summary">
            <span><strong>{loading ? "…" : analysis.models.length}</strong> {analysis.models.length === 1 ? "model" : "models"}</span>
            <span><strong>{loading ? "…" : formatCount(analysis.scoreRunCount)}</strong> scores</span>
            <span><strong>{loading ? "…" : formatCount(analysis.costRunCount)}</strong> costs</span>
          </div>
        )}
      >
        <label className="inline-select compact-inline-select">
          <span>Cost scale</span>
          <select aria-label="Cost scale" value={state.scale} onChange={(event) => replaceValue("scale", event.target.value, "log")}>
            <option value="log">Logarithmic</option>
            <option value="linear">Linear</option>
          </select>
        </label>
      </FilterBar>

      <section className="analysis-panel cost-analysis">
        <header className="panel-heading">
          <div>
            <h2>Mean score vs. estimated API cost</h2>
            <p>Costs use independently dated, frozen pricing profiles.</p>
          </div>
          <HighlightActions selection={highlights}>
            <button className="secondary-button" type="button" disabled={exporting || loading || analysis.models.length === 0} onClick={exportRecords}
              title="Export per-model score and estimated cost aggregates for the active filters (CSV)">
              {exporting ? "Preparing…" : "Export"}
            </button>
          </HighlightActions>
        </header>

        {loading ? (
          <div className="analysis-loading" aria-live="polite"><i /><i /><i /><span>Loading cost records…</span></div>
        ) : error ? (
          <div className="empty-state">
            <p className="eyebrow">Data error</p>
            <h2>The cost observations could not be loaded.</h2>
            <p>{error.message}</p>
            <button className="secondary-button" type="button" onClick={() => setRetry((value) => value + 1)}>Try again</button>
          </div>
        ) : analysis.plottedModels.length > 0 ? (
          <>
            <VegaChart
              spec={chartSpec}
              ariaLabel={`Cost efficiency chart for ${analysis.plottedModels.length} models, ${analysis.scoreRunCount} scored runs, and ${analysis.costRunCount} costed runs`}
              onDatumClick={openPoint}
              interactiveMarkSelector=".cost_points path"
              highlight={{ selection: highlights, markSelector: ".cost_points path", getId: modelHighlightId }}
              fitContainerWidth
            />
            <ParetoLegend />
            {(analysis.unavailableCostRunCount > 0 || analysis.unpricedModelCount > 0) && (
              <p className="chart-footnote">
                {analysis.unavailableCostRunCount > 0 && `${formatCount(analysis.unavailableCostRunCount)} scored ${analysis.unavailableCostRunCount === 1 ? "run has" : "runs have"} no cost estimate.`}
                {analysis.unavailableCostRunCount > 0 && analysis.unpricedModelCount > 0 ? " " : ""}
                {analysis.unpricedModelCount > 0 && `${formatCount(analysis.unpricedModelCount)} ${analysis.unpricedModelCount === 1 ? "model has" : "models have"} no pricing profile.`}
              </p>
            )}
          </>
        ) : (
          <div className="empty-state">
            <p className="eyebrow">No cost observations</p>
            <h2>This filter combination has no costed runs.</h2>
            <button className="secondary-button" type="button" onClick={reset}>Clear filters</button>
          </div>
        )}
      </section>

      {!loading && !error && analysis.models.length > 0 && (
        <details className="accessible-data cost-data">
          <summary>Accessible cost efficiency table</summary>
          <div className="table-scroll">
            <table>
              <caption>Per-model aggregates for the active cost efficiency selection</caption>
              <thead>
                <tr><th scope="col">Model</th><th scope="col">Mean score</th><th scope="col">Estimated mean cost</th><th scope="col">Pareto front</th><th scope="col">Score n</th><th scope="col">Cost n</th><th scope="col">Mean priced tokens</th><th scope="col">Observed effective rate</th><th scope="col">Pricing</th><th scope="col">Method</th><th scope="col">Sources</th><th scope="col">Records</th><th scope="col">Highlighted</th></tr>
              </thead>
              <tbody>
                {analysis.models.map((summary) => (
                  <tr key={summary.modelId} className={highlights.selected.has(summary.modelId) ? "is-highlighted" : undefined}>
                    <th scope="row">{summary.modelLabel}</th>
                    <td className="numeric">{formatScore(summary.meanScore)}</td>
                    <td className="numeric">{formatUsd(summary.meanEstimatedCostUsd)}</td>
                    <td>{!plottedModels.has(summary.modelId) ? "Not evaluated" : paretoModels.has(summary.modelId) ? "Yes" : "No"}</td>
                    <td className="numeric">{formatCount(summary.scoreRunCount)}</td>
                    <td className="numeric">{formatCount(summary.costRunCount)}</td>
                    <td className="numeric">{formatCount(summary.meanPricedTokens)}</td>
                    <td className="numeric">{formatUsdPerMillion(summary.effectiveObservedPriceUsdPerMillion)}</td>
                    <td>{summary.pricingProvider ?? "Unavailable"}<small>{summary.pricingProviderTag ? ` · ${summary.pricingProviderTag}` : ""}</small></td>
                    <td>{summary.costMethod}</td>
                    <td>{pricingLinks(summary)}</td>
                    <td><Link to={runsPath(summary.modelId, state, params)}>Open runs</Link></td>
                    <td><HighlightCheckbox selection={highlights} id={summary.modelId} label={summary.modelLabel} /></td>
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
