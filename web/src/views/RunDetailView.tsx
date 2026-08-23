import { useEffect, useState, type CSSProperties } from "react";
import { Link, useLocation, useParams } from "react-router-dom";

import { PageIntro } from "../components/PageIntro";
import { loadRunById } from "../data/client";
import { useDataset } from "../data/context";
import type { RunRecord } from "../data/types";
import { formatMilliseconds } from "../utils/format";

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

  useEffect(() => {
    let active = true;
    loadRunById(manifest, id).then((loaded) => {
      if (active) setRun(loaded);
    }).catch((reason: unknown) => {
      if (active) setError(reason instanceof Error ? reason : new Error(String(reason)));
    });
    return () => { active = false; };
  }, [id, manifest]);

  const returnParams = new URLSearchParams(location.search);
  const origin = returnParams.get("from");
  returnParams.delete("from");
  const returnQuery = returnParams.toString();
  const originPath = origin === "scores" ? "/scores" : origin === "performance" ? "/performance" : "/runs";
  const originLabel = origin === "scores" ? "model scores" : origin === "performance" ? "performance" : "runs";
  const backPath = `${originPath}${returnQuery ? `?${returnQuery}` : ""}`;
  const backLabel = origin === "scores" ? "Back to model scores" : origin === "performance" ? "Back to performance" : "Back to matching runs";
  if (error) return <main id="main-content" className="page-shell"><div className="empty-state"><p className="eyebrow">Data error</p><h1>The result could not be loaded.</h1><p>{error.message}</p><Link to={backPath}>Return to {originLabel}</Link></div></main>;
  if (run === undefined) return <main id="main-content" className="page-shell"><div className="detail-loading">Loading run evidence…</div></main>;
  if (run === null) return <main id="main-content" className="page-shell"><div className="empty-state"><p className="eyebrow">Unknown result</p><h1>No run has this identifier.</h1><Link to={backPath}>Return to {originLabel}</Link></div></main>;

  const band = manifest.scoreScale.bands.find((candidate) => candidate.id === run.scoreBandId);
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
          <Link to={`/scores?${tierQuery}`}>This model in Model scores <span>→</span></Link>
          <Link to={`/performance?${performanceQuery}`}>Performance in this benchmark cell <span>→</span></Link>
          <Link to={`/runs?${cellQuery}`}>All runs in this benchmark cell <span>→</span></Link>
        </aside>
      </div>
    </main>
  );
}
