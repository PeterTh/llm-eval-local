import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { analyzeTime } from "../analysis/time";
import { FilterBar } from "../components/FilterBar";
import { HighlightActions, HighlightCheckbox } from "../components/HighlightActions";
import { ParetoLegend } from "../components/ParetoLegend";
import { TimeDistributionChart, TimeScatterChart } from "../components/TimeCharts";
import { loadTimeDataset } from "../data/client";
import { useDataset } from "../data/context";
import type { FilterState, TimeDataset } from "../data/types";
import { useFilterState } from "../state/filters";
import { copyHighlights, useHighlightState } from "../state/highlights";
import { downloadText, timeSummariesToCsv } from "../utils/csv";
import { formatCount, formatGenerationTime, formatScore } from "../utils/format";

function runsPath(modelId: string, filters: Pick<FilterState, "benchmarks" | "backends">, current: URLSearchParams): string {
  const query = copyHighlights(current);
  query.append("model", modelId);
  filters.benchmarks.forEach((value) => query.append("benchmark", value));
  filters.backends.forEach((value) => query.append("backend", value));
  return `/runs?${query}`;
}

export function TimeView() {
  const { manifest } = useDataset();
  const { state, params, replaceValues, replaceValue, reset } = useFilterState(manifest, { defaultScale: "linear" });
  const navigate = useNavigate();
  const [dataset, setDataset] = useState<TimeDataset | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [retry, setRetry] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    loadTimeDataset(manifest).then((loaded) => {
      if (active) setDataset(loaded);
    }).catch((reason: unknown) => {
      if (active) setError(reason instanceof Error ? reason : new Error(String(reason)));
    }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [manifest, retry]);

  const analysis = useMemo(() => analyzeTime(dataset ?? { schemaVersion: 1, sourceDigest: manifest.scoringDigest, runs: [] }, manifest, state), [dataset, manifest, state]);
  const paretoModels = new Set(analysis.paretoModelIds);
  const highlights = useHighlightState("modelIds", analysis.plottedModels.map((model) => model.modelId));
  const plottedModels = new Set(analysis.plottedModels.map((model) => model.modelId));
  const openModel = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.modelId === "string") navigate(runsPath(datum.modelId, state, params));
  }, [navigate, state, params]);
  const openRun = useCallback((datum: Record<string, unknown>) => {
    if (typeof datum.runId !== "string") return;
    const query = copyHighlights(params);
    for (const key of ["model", "model-set", "benchmark", "backend", "scale"]) {
      params.getAll(key).forEach((value) => query.append(key, value));
    }
    query.set("from", "time");
    navigate(`/run/${encodeURIComponent(datum.runId)}?${query}`);
  }, [navigate, params]);

  return (
    <main id="main-content" className="page-shell">
      <header className="view-summary">
        <h1 className="sr-only">Time Efficiency</h1>
        <p>Mean overall score is compared with the time each agent spent generating a program in the active subset.</p>
      </header>
      <FilterBar
        manifest={manifest} filters={{ ...state, scoreBands: [], outcome: "all" }}
        onModels={(values) => replaceValues("model", values)} onBenchmarks={(values) => replaceValues("benchmark", values)}
        onBackends={(values) => replaceValues("backend", values)} onReset={reset}
        additionalActiveCount={state.scale === "linear" ? 0 : 1}
        resultSummary={(
          <div className="filter-result-summary" aria-label="Current time efficiency selection summary">
            <span><strong>{loading ? "…" : analysis.models.length}</strong> {analysis.models.length === 1 ? "model" : "models"}</span>
            <span><strong>{loading ? "…" : formatCount(analysis.scoreRunCount)}</strong> scores</span>
            <span><strong>{loading ? "…" : formatCount(analysis.timeRunCount)}</strong> times</span>
          </div>
        )}
      >
        <label className="inline-select compact-inline-select">
          <span>Time scale</span>
          <select aria-label="Time scale" value={state.scale} onChange={(event) => replaceValue("scale", event.target.value, "linear")}>
            <option value="linear">Linear</option><option value="log">Logarithmic</option>
          </select>
        </label>
      </FilterBar>

      <section className="analysis-panel time-analysis">
        <header className="panel-heading">
          <div>
            <h2>Mean score vs. generation time</h2>
            <p>Generation time includes tool execution and excludes documented retry waits.</p>
          </div>
          <HighlightActions selection={highlights}>
          <button className="secondary-button" type="button" disabled={loading || error !== null || analysis.models.length === 0}
            title="Export per-model score and generation-time aggregates for the active filters (CSV)"
            onClick={() => downloadText("llm-eval-score-time.csv", timeSummariesToCsv(analysis.models), "text/csv;charset=utf-8")}>
            Export
          </button>
          </HighlightActions>
        </header>
        {loading ? (
          <div className="analysis-loading" aria-live="polite"><i /><i /><i /><span>Loading time records…</span></div>
        ) : error ? (
          <div className="empty-state">
            <p className="eyebrow">Data error</p><h2>The time observations could not be loaded.</h2><p>{error.message}</p>
            <button className="secondary-button" type="button" onClick={() => setRetry((value) => value + 1)}>Try again</button>
          </div>
        ) : analysis.plottedModels.length > 0 ? (
          <>
            <TimeScatterChart analysis={analysis} manifest={manifest} scale={state.scale} onDatumClick={openModel} highlights={highlights} />
            <ParetoLegend />
          </>
        ) : (
          <div className="empty-state">
            <p className="eyebrow">{analysis.scoreRunCount === 0 ? "No scored runs" : "No time observations"}</p>
            <h2>{analysis.scoreRunCount === 0 ? "This filter combination has no scored runs." : "Generation times are unavailable for this selection."}</h2>
            <button className="secondary-button" type="button" onClick={reset}>Clear filters</button>
          </div>
        )}
        {!loading && !error && analysis.unavailableTimeRunCount > 0 && (
          <p className="chart-footnote">{formatCount(analysis.unavailableTimeRunCount)} scored runs have no generation time. Score means include all selected runs; time statistics use available durations.</p>
        )}
      </section>

      {!loading && !error && analysis.plottedModels.length > 0 && (
        <section className="analysis-panel time-distribution">
          <header className="panel-heading"><div>
            <h2>Generation-time distributions</h2>
            <p>Boxes show the middle 50% of runs, the line marks the median, and diamonds mark the mean. Whiskers extend to observations within 1.5× the interquartile range. Select an outlier to inspect its result.</p>
          </div></header>
          <TimeDistributionChart analysis={analysis} manifest={manifest} scale={state.scale} onDatumClick={openRun} />
          <p className="chart-footnote">All selected outcomes are included. Models are ordered by mean time, longest first. Each chart shows its own complete time range.</p>
        </section>
      )}
      {!loading && !error && analysis.models.length > 0 && (
        <details className="accessible-data time-data">
          <summary>Accessible time efficiency table</summary>
          <div className="table-scroll"><table>
            <caption>Per-model generation-time aggregates for the active selection; durations in minutes</caption>
            <thead><tr>
              <th scope="col">Model</th><th scope="col">Mean score</th><th scope="col">Pareto front</th><th scope="col">Scored n</th><th scope="col">Timed n</th><th scope="col">Missing n</th>
              <th scope="col">Mean</th><th scope="col">Median</th><th scope="col">Q1</th><th scope="col">Q3</th>
              <th scope="col">Lower whisker</th><th scope="col">Upper whisker</th><th scope="col">Minimum</th><th scope="col">Maximum</th><th scope="col">Outliers</th><th scope="col">Records</th><th scope="col">Highlighted</th>
            </tr></thead>
            <tbody>{analysis.models.map((model) => {
              const stats = model.distribution;
              return <tr key={model.modelId} className={highlights.selected.has(model.modelId) ? "is-highlighted" : undefined}>
                <th scope="row">{model.modelLabel}</th><td className="numeric">{formatScore(model.meanScore)}</td>
                <td>{!plottedModels.has(model.modelId) ? "Not evaluated" : paretoModels.has(model.modelId) ? "Yes" : "No"}</td>
                <td className="numeric">{formatCount(model.scoreRunCount)}</td><td className="numeric">{formatCount(model.timeRunCount)}</td><td className="numeric">{formatCount(model.unavailableTimeRunCount)}</td>
                {[model.meanGenerationTimeSeconds, stats?.median, stats?.firstQuartile, stats?.thirdQuartile, stats?.lowerWhisker, stats?.upperWhisker, stats?.minimum, stats?.maximum].map((seconds, index) => <td className="numeric" key={index}>{formatGenerationTime(seconds ?? null)}</td>)}
                <td className="numeric">{formatCount(stats?.outlierCount ?? null)}</td><td><Link to={runsPath(model.modelId, state, params)}>Open runs</Link></td>
                <td><HighlightCheckbox selection={highlights} id={model.modelId} label={model.modelLabel} /></td>
              </tr>;
            })}</tbody>
          </table></div>
        </details>
      )}
    </main>
  );
}
