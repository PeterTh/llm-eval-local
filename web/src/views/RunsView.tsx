import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";

import { filterRuns, sortRuns, type BenchmarkOutcome, type RunSort, type ValidationOutcome } from "../analysis/runs";
import { FilterBar } from "../components/FilterBar";
import { FilterMenu } from "../components/FilterMenu";
import { loadRuns } from "../data/client";
import { useDataset } from "../data/context";
import type { EntityMetadata, RunRecord } from "../data/types";
import { useFilterState } from "../state/filters";
import { downloadText, runsToCsv } from "../utils/csv";
import { formatMilliseconds } from "../utils/format";

const pageSize = 50;
const validationOutcomes = new Set<ValidationOutcome>(["all", "passed", "failed"]);
const benchmarkOutcomes = new Set<BenchmarkOutcome>(["all", "successful", "failed", "unavailable"]);
const runSorts = new Set<RunSort>(["model", "score-desc", "score-asc", "cell"]);

function updateParam(setParams: ReturnType<typeof useFilterState>["setParams"], key: string, value: string, defaultValue = "") {
  setParams((current) => {
    const next = new URLSearchParams(current);
    if (!value || value === defaultValue) next.delete(key);
    else next.set(key, value);
    if (key !== "page") next.delete("page");
    return next;
  });
}

function outcomeLabel(run: RunRecord): string {
  if (run.benchmarkSuccess === true) return "Successful";
  if (run.benchmarkSuccess === false) return "Failed";
  return "Not run";
}

export function RunsView() {
  const { manifest, labels } = useDataset();
  const { state, params, setParams, replaceValues, reset } = useFilterState(manifest);
  const [runs, setRuns] = useState<RunRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
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
    // Stable joined keys prevent refetching when unrelated URL controls change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [manifest, benchmarkKey, backendKey]);

  const exactScoreValue = params.get("score");
  const exactScore = exactScoreValue !== null && /^\d+$/.test(exactScoreValue)
    && Number(exactScoreValue) >= manifest.scoreScale.minimum && Number(exactScoreValue) <= manifest.scoreScale.maximum
    ? Number(exactScoreValue) : null;
  const validationCandidate = params.get("validation") as ValidationOutcome | null;
  const validation = validationCandidate && validationOutcomes.has(validationCandidate) ? validationCandidate : "all";
  const benchmarkCandidate = params.get("outcome") as BenchmarkOutcome | null;
  const benchmark = benchmarkCandidate && benchmarkOutcomes.has(benchmarkCandidate) ? benchmarkCandidate : "all";
  const sortCandidate = params.get("runSort") as RunSort | null;
  const runSort = sortCandidate && runSorts.has(sortCandidate) ? sortCandidate : "model";
  const query = params.get("q") ?? "";
  const pageCandidate = Number(params.get("page") ?? "1");

  const filtered = useMemo(() => filterRuns(runs, {
    models: state.models,
    scoreBands: state.scoreBands,
    exactScore,
    validation,
    benchmark,
    query,
  }), [benchmark, exactScore, query, runs, state.models, state.scoreBands, validation]);
  const sorted = useMemo(() => sortRuns(filtered, runSort, labels.models), [filtered, labels.models, runSort]);
  const pageCount = Math.max(1, Math.ceil(sorted.length / pageSize));
  const page = Number.isInteger(pageCandidate) ? Math.min(Math.max(pageCandidate, 1), pageCount) : 1;
  const pageRuns = sorted.slice((page - 1) * pageSize, page * pageSize);
  const bandEntities: EntityMetadata[] = manifest.scoreScale.bands.map((band) => ({ id: band.id, label: `${band.label} · ${band.detail}` }));
  const queryString = params.toString();

  return (
    <main id="main-content" className="page-shell">
      <header className="view-summary">
        <h1 className="sr-only">Runs</h1>
        <p>Search and filter scored records. Each result links to commit-pinned generated source and its exact validation and benchmark evidence.</p>
      </header>

      <FilterBar
        manifest={manifest}
        filters={state}
        onModels={(values) => replaceValues("model", values)}
        onBenchmarks={(values) => replaceValues("benchmark", values)}
        onBackends={(values) => replaceValues("backend", values)}
        onReset={reset}
        additionalActiveCount={(query ? 1 : 0) + (exactScore === null ? 0 : 1) + (validation === "all" ? 0 : 1)
          + (runSort === "model" ? 0 : 1) + (page === 1 ? 0 : 1)}
        resultSummary={(
          <div className="filter-result-summary" aria-label="Run result summary">
            <span><strong>{loading ? "…" : filtered.length.toLocaleString()}</strong> matching</span>
            <span><strong>{loading ? "…" : runs.length.toLocaleString()}</strong> loaded</span>
          </div>
        )}
      >
        <FilterMenu label="Score bands" entities={bandEntities} selected={state.scoreBands} onChange={(values) => replaceValues("band", values)} />
      </FilterBar>

      <section className="run-controls" aria-label="Run search and outcomes">
        <label className="search-field run-search">
          <span>Search runs</span>
          <input type="search" value={query} onChange={(event) => updateParam(setParams, "q", event.target.value)} placeholder="Run ID, model, benchmark…" />
        </label>
        <label>
          <span>Exact score</span>
          <select value={exactScore ?? ""} onChange={(event) => updateParam(setParams, "score", event.target.value)}>
            <option value="">All scores</option>
            {Array.from({ length: manifest.scoreScale.maximum - manifest.scoreScale.minimum + 1 }, (_, index) => index + manifest.scoreScale.minimum)
              .map((score) => <option key={score} value={score}>{score}</option>)}
          </select>
        </label>
        <label>
          <span>Validation</span>
          <select value={validation} onChange={(event) => updateParam(setParams, "validation", event.target.value, "all")}>
            <option value="all">All outcomes</option><option value="passed">Passed</option><option value="failed">Stopped early</option>
          </select>
        </label>
        <label>
          <span>Benchmark</span>
          <select value={benchmark} onChange={(event) => updateParam(setParams, "outcome", event.target.value, "all")}>
            <option value="all">All outcomes</option><option value="successful">Successful</option><option value="failed">Failed</option><option value="unavailable">Not run</option>
          </select>
        </label>
        <label>
          <span>Sort</span>
          <select value={runSort} onChange={(event) => updateParam(setParams, "runSort", event.target.value, "model")}>
            <option value="model">Model</option><option value="score-desc">Score · high first</option><option value="score-asc">Score · low first</option><option value="cell">Benchmark + backend</option>
          </select>
        </label>
      </section>

      <section className="records-panel">
        <header className="panel-heading records-heading">
          <div aria-live="polite">
            <h2>{loading ? "Loading run evidence…" : `${filtered.length.toLocaleString()} matching runs`}</h2>
            {!loading && filtered.length > 0 && <p>Showing {(page - 1) * pageSize + 1}–{Math.min(page * pageSize, filtered.length)} of {filtered.length.toLocaleString()}</p>}
          </div>
          <button className="secondary-button" type="button" disabled={loading || filtered.length === 0} onClick={() => downloadText("llm-eval-runs.csv", runsToCsv(sorted), "text/csv;charset=utf-8")}>Export selection · CSV</button>
        </header>

        {error ? (
          <div className="empty-state"><p className="eyebrow">Data error</p><h2>Run shards could not be loaded.</h2><p>{error.message}</p></div>
        ) : loading ? (
          <div className="table-loading" aria-label="Loading"><i /><i /><i /></div>
        ) : pageRuns.length === 0 ? (
          <div className="empty-state"><p className="eyebrow">No matches</p><h2>No runs satisfy all active filters.</h2><button className="secondary-button" type="button" onClick={reset}>Clear filters</button></div>
        ) : (
          <div className="table-scroll run-table-wrap">
            <table className="run-table">
              <caption className="sr-only">Individual evaluation runs matching the active filters</caption>
              <thead><tr><th scope="col">Run</th><th scope="col">Model</th><th scope="col">Benchmark</th><th scope="col">Backend</th><th scope="col">Rep.</th><th scope="col">Score</th><th scope="col">Validation</th><th scope="col">Benchmark</th><th scope="col">Median</th><th scope="col">Source</th></tr></thead>
              <tbody>
                {pageRuns.map((run) => {
                  const detailPath = `/run/${encodeURIComponent(run.id)}${queryString ? `?${queryString}` : ""}`;
                  return (
                    <tr key={run.id}>
                      <th scope="row">
                        <Link className="run-id-link" to={detailPath}>{run.id}</Link>
                        {run.timingFixed && <span className="timing-fixed-label">Timing fixed</span>}
                      </th>
                      <td>{labels.models.get(run.modelId) ?? run.modelId}</td>
                      <td>{labels.benchmarks.get(run.benchmarkId) ?? run.benchmarkId}</td>
                      <td><span className="backend-tag">{labels.backends.get(run.backendId) ?? run.backendId}</span></td>
                      <td>{run.repetition}</td>
                      <td><span className={`score-chip band-${run.scoreBandId}`}>{run.overallScore}</span></td>
                      <td><span className={`status-dot ${run.validationStatus === 5 ? "success" : "failure"}`} />{run.validationStatus === 5 ? "Passed" : `Stage ${run.validationStatus}`}</td>
                      <td>{outcomeLabel(run)}</td>
                      <td className="numeric">{formatMilliseconds(run.benchmarkMedianMs)}</td>
                      <td><a className="source-arrow" href={run.sourceUrl} target="_blank" rel="noreferrer" aria-label={`Open ${run.timingFixed ? "timing-corrected " : ""}source for ${run.id}`}>↗</a></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {!loading && filtered.length > 0 && (
          <nav className="pagination" aria-label="Run table pages">
            <button type="button" disabled={page === 1} onClick={() => updateParam(setParams, "page", String(page - 1), "1")}>← Previous</button>
            <span>Page <strong>{page}</strong> of {pageCount}</span>
            <button type="button" disabled={page === pageCount} onClick={() => updateParam(setParams, "page", String(page + 1), "1")}>Next →</button>
          </nav>
        )}
      </section>
    </main>
  );
}
