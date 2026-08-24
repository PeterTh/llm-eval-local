import { useEffect, useState, type CSSProperties } from "react";
import { Link, useLocation, useParams } from "react-router-dom";

import { pricedTokenCountForRun } from "../analysis/cost";
import { PageIntro } from "../components/PageIntro";
import { loadCostDataset, loadRunById } from "../data/client";
import { useDataset } from "../data/context";
import type { CostDataset, RunRecord } from "../data/types";
import { formatCount, formatMilliseconds, formatUsd } from "../utils/format";

function boolLabel(value: boolean | null): string {
  if (value === true) return "Passed";
  if (value === false) return "Failed";
  return "Not reached";
}

export function RunDetailView() {
  const { manifest, labels } = useDataset();
  const { id = "" } = useParams();
  const location = useLocation();
  const [run, setRun] = useState<RunRecord | null | undefined>(undefined);
  const [error, setError] = useState<Error | null>(null);
  const [costDataset, setCostDataset] = useState<CostDataset | undefined>(undefined);
  const [costError, setCostError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    loadRunById(manifest, id).then((loaded) => {
      if (active) setRun(loaded);
    }).catch((reason: unknown) => {
      if (active) setError(reason instanceof Error ? reason : new Error(String(reason)));
    });
    return () => { active = false; };
  }, [id, manifest]);

  useEffect(() => {
    let active = true;
    setCostDataset(undefined);
    setCostError(null);
    loadCostDataset(manifest).then((loaded) => {
      if (active) setCostDataset(loaded);
    }).catch((reason: unknown) => {
      if (active) setCostError(reason instanceof Error ? reason : new Error(String(reason)));
    });
    return () => { active = false; };
  }, [manifest]);

  const returnParams = new URLSearchParams(location.search);
  const origin = returnParams.get("from");
  returnParams.delete("from");
  const returnQuery = returnParams.toString();
  const originPath = origin === "scores" ? "/scores" : origin === "performance" ? "/performance" : "/runs";
  const originLabel = origin === "scores" ? "Model Scores" : origin === "performance" ? "performance" : "runs";
  const backPath = `${originPath}${returnQuery ? `?${returnQuery}` : ""}`;
  const backLabel = origin === "scores" ? "Back to Model Scores" : origin === "performance" ? "Back to performance" : "Back to matching runs";
  if (error) return <main id="main-content" className="page-shell"><div className="empty-state"><p className="eyebrow">Data error</p><h1>The result could not be loaded.</h1><p>{error.message}</p><Link to={backPath}>Return to {originLabel}</Link></div></main>;
  if (run === undefined) return <main id="main-content" className="page-shell"><div className="detail-loading">Loading run evidence…</div></main>;
  if (run === null) return <main id="main-content" className="page-shell"><div className="empty-state"><p className="eyebrow">Unknown result</p><h1>No run has this identifier.</h1><Link to={backPath}>Return to {originLabel}</Link></div></main>;

  const band = manifest.scoreScale.bands.find((candidate) => candidate.id === run.scoreBandId);
  const costRun = costDataset?.runs.find((candidate) => candidate.id === run.id) ?? null;
  const costProfile = costRun?.pricingProfileId
    ? costDataset?.profiles.find((candidate) => candidate.id === costRun.pricingProfileId) ?? null
    : null;
  const tokenConvention = costDataset?.inputTokenAccounting[run.modelId] ?? "includes-cached";
  const pricedTokens = costRun ? pricedTokenCountForRun(costRun, tokenConvention) : null;
  const hasSplitTokens = costRun !== null
    && costRun.inputTokens !== null
    && costRun.cachedInputTokens !== null
    && costRun.outputTokens !== null;
  const tierQuery = new URLSearchParams();
  tierQuery.append("model", run.modelId);
  const performanceQuery = new URLSearchParams();
  for (const key of ["model", "model-set"]) {
    returnParams.getAll(key).forEach((value) => performanceQuery.append(key, value));
  }
  performanceQuery.append("benchmark", run.benchmarkId);
  performanceQuery.append("backend", run.backendId);
  performanceQuery.set("focus", run.modelId);
  const cellQuery = new URLSearchParams();
  cellQuery.append("benchmark", run.benchmarkId);
  cellQuery.append("backend", run.backendId);
  const costQuery = new URLSearchParams(cellQuery);
  costQuery.append("model", run.modelId);

  return (
    <main id="main-content" className="page-shell detail-page">
      <Link className="back-link" to={backPath}>← {backLabel}</Link>
      <PageIntro
        eyebrow="Individual result"
        title={run.id}
        description={<>{labels.models.get(run.modelId) ?? run.modelId} · {labels.benchmarks.get(run.benchmarkId) ?? run.benchmarkId} · {labels.backends.get(run.backendId) ?? run.backendId} · repetition {run.repetition}</>}
        aside={(
          <div className="score-medallion" style={{ "--band-color": band?.color ?? "#64727d" } as CSSProperties}>
            <strong>{run.overallScore}</strong><span>/ {manifest.scoreScale.maximum}</span><small>{band?.label ?? run.scoreBandId}</small>
          </div>
        )}
      />

      <div className="detail-grid">
        <section className="detail-card validation-card">
          <p className="eyebrow">Validation</p>
          <h2>{run.validationStatus === 5 ? "Validation passed" : `Stopped at stage ${run.validationStatus}`}</h2>
          <p>{run.validationMessage || "No validation message was recorded."}</p>
          <ol className="stage-list">
            {Object.entries(run.validationStages).map(([stage, value]) => (
              <li key={stage} className={value === true ? "passed" : value === false ? "failed" : "unreached"}>
                <i aria-hidden="true" /><span>{stage.replaceAll("_", " ")}</span><strong>{boolLabel(value)}</strong>
              </li>
            ))}
          </ol>
        </section>

        <section className="detail-card performance-card">
          <p className="eyebrow">Performance</p>
          <h2>{run.benchmarkMedianMs === null ? "No benchmark result" : `${formatMilliseconds(run.benchmarkMedianMs)} median`}</h2>
          <p>{run.benchmarkSuccess === true ? "Successful benchmark execution." : run.benchmarkSuccess === false ? "Benchmark execution failed." : "Validation did not produce a benchmarkable program."}</p>
          {run.benchmarkMeasurementsMs.length > 0 && (
            <div className="measurement-list" aria-label="Five benchmark measurements">
              {run.benchmarkMeasurementsMs.map((measurement, index) => (
                <div key={`${measurement}-${index}`}><span>Run {index + 1}</span><strong>{formatMilliseconds(measurement)}</strong></div>
              ))}
            </div>
          )}
        </section>

        <section className="detail-card cost-card" aria-labelledby="run-cost-heading">
          <p className="eyebrow">Tokens and cost</p>
          <h2 id="run-cost-heading">
            {costError
              ? "Cost data unavailable"
              : costDataset === undefined
                ? "Loading token and cost data…"
                : costRun === null
                  ? "No token or cost record"
                  : costRun.estimatedCostUsd === null
                    ? "Estimated API cost unavailable"
                    : `${formatUsd(costRun.estimatedCostUsd)} estimated API cost`}
          </h2>
          <p>
            {costError
              ? costError.message
              : costDataset === undefined
                ? "Loading the frozen cost record for this run."
                : costRun === null
                  ? "No cost record was generated for this scored run."
                  : costProfile
                    ? `${costProfile.pricingProvider} · ${costProfile.pricingProviderTag} · pricing snapshot ${costProfile.pricingAsOf}.`
                    : "Token counts are recorded, but no pricing profile is available."}
          </p>
          {costRun && (
            <div className="measurement-list" aria-label="Token consumption">
              <div><span>{hasSplitTokens ? "Priced token volume" : "Combined tokens"}</span><strong>{formatCount(pricedTokens)}</strong></div>
              {hasSplitTokens && (
                <>
                  <div><span>{tokenConvention === "excludes-cached" ? "Uncached input tokens" : "Input tokens (cache included)"}</span><strong>{formatCount(costRun.inputTokens)}</strong></div>
                  <div><span>Cached input tokens</span><strong>{formatCount(costRun.cachedInputTokens)}</strong></div>
                  <div><span>Output tokens</span><strong>{formatCount(costRun.outputTokens)}</strong></div>
                </>
              )}
            </div>
          )}
        </section>

        <section className="detail-card provenance-card">
          <p className="eyebrow">Primary evidence</p>
          <h2>Commit-pinned provenance</h2>
          <p>These links resolve to the exact repositories and revisions used to build this explorer.</p>
          <div className="evidence-links">
            <a href={run.sourceUrl} target="_blank" rel="noreferrer"><span>Generated source directory</span><strong>Open on GitHub ↗</strong></a>
            <a href={run.validationEvidenceUrl} target="_blank" rel="noreferrer"><span>Validation JSONL evidence</span><strong>Open exact line ↗</strong></a>
            {run.benchmarkEvidenceUrl && <a href={run.benchmarkEvidenceUrl} target="_blank" rel="noreferrer"><span>Benchmark JSONL evidence</span><strong>Open exact line ↗</strong></a>}
          </div>
          <dl className="provenance-list">
            <div><dt>Source batch</dt><dd>{run.sourceBatch}</dd></div>
            <div><dt>Source path</dt><dd><code>{run.sourcePath}</code></dd></div>
            <div><dt>Artifact commit</dt><dd><code>{manifest.artifactCommit}</code></dd></div>
          </dl>
        </section>

        <aside className="detail-card related-card">
          <p className="eyebrow">Related data</p>
          <h2>Related views</h2>
          <Link to={`/tiers?${tierQuery}`}>This model in Tiered Success <span>→</span></Link>
          <Link to={`/scores?${tierQuery}`}>This model in Model Scores <span>→</span></Link>
          <Link to={`/performance?${performanceQuery}`}>Performance in this benchmark cell <span>→</span></Link>
          <Link to={`/cost?${costQuery}`}>This model in Cost Efficiency <span>→</span></Link>
          <Link to={`/runs?${cellQuery}`}>All runs in this benchmark cell <span>→</span></Link>
        </aside>
      </div>
    </main>
  );
}
