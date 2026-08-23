import { PageIntro } from "../components/PageIntro";
import { useDataset } from "../data/context";
import type { ModelMetadata } from "../data/types";

function formatEntityList(labels: string[]): string {
  if (labels.length === 0) return "none";
  if (labels.length === 1) return labels[0]!;
  if (labels.length === 2) return `${labels[0]!} and ${labels[1]!}`;
  return `${labels.slice(0, -1).join(", ")}, and ${labels.at(-1)}`;
}

function formatGpuInventory(gpus: Array<{ model: string; memoryMiB: number }>): string {
  const groups = new Map<string, { count: number; model: string; memoryMiB: number }>();
  for (const gpu of gpus) {
    const key = `${gpu.model}\u0000${gpu.memoryMiB}`;
    const group = groups.get(key) ?? { count: 0, model: gpu.model, memoryMiB: gpu.memoryMiB };
    group.count += 1;
    groups.set(key, group);
  }
  if (groups.size === 0) return "No GPU recorded";
  return [...groups.values()].map((group) =>
    `${group.count} × ${group.model} (${group.memoryMiB.toLocaleString("en-US")} MiB each)`).join("; ");
}

function modelInvocationTitle(model: ModelMetadata, harnessLabel: string): string {
  if (!model.invocation) return "No invocation metadata recorded";
  const effort = model.invocation.reasoningEffort ? `; reasoning effort ${model.invocation.reasoningEffort}` : "";
  return `${harnessLabel}; invoked model ${model.invocation.invokedModelId}${effort}`;
}

export function MethodologyView() {
  const { manifest } = useDataset();
  const artifactRoot = `${manifest.artifactRepository}/tree/${manifest.artifactCommit}`;
  const artifactBlob = `${manifest.artifactRepository}/blob/${manifest.artifactCommit}`;
  const backendLabels = formatEntityList(manifest.backends.map((backend) => backend.label));
  const harnesses = manifest.methodology.harnesses.map((harness) => ({
    ...harness,
    models: manifest.models.filter((model) => model.invocation?.harnessId === harness.id),
  }));
  const modelsWithoutHarness = manifest.models.filter((model) => !model.invocation);
  const system = manifest.methodology.executionSystem;
  const backendLabel = new Map(manifest.backends.map((backend) => [backend.id, backend.label]));
  const experiment = manifest.methodology.experimentScript;
  const experimentUrl = `${experiment.repository}/blob/${experiment.commit}/${experiment.path.split("/").map(encodeURIComponent).join("/")}`;

  return (
    <main id="main-content" className="page-shell methodology-page">
      <PageIntro
        eyebrow="Study design"
        title="Methodology"
        description={<>Summary of the program generation, validation, performance measurement, and scoring procedure represented by this dataset snapshot.</>}
        aside={(
          <div className="metric-strip" aria-label="Dataset design summary">
            <div><strong>{manifest.counts.runs.toLocaleString()}</strong><span>runs</span></div>
            <div><strong>5</strong><span>validation stages</span></div>
            <div><strong>{manifest.scoreScale.minimum}–{manifest.scoreScale.maximum}</strong><span>score range</span></div>
          </div>
        )}
      />

      <div className="methodology-layout">
        <div className="methodology-main">
          <section className="methodology-section" aria-labelledby="method-unit">
            <p className="eyebrow">Experimental unit</p>
            <h2 id="method-unit">LLM-generated parallel programs</h2>
            <p>
              Each record represents one LLM-agent invocation for a model, a sequential benchmark application,
              a requested parallelization backend, and a repetition. The same concise prompt template is adapted
              to the benchmark and backend but not otherwise varied between models. The agent harness varies by model
              as recorded below. Each invocation starts from
              the sequential source in an isolated user environment; the resulting program and invocation metadata
              are retained for later evaluation.
            </p>
            <p>
              The current snapshot contains {manifest.counts.runs.toLocaleString()} records across {manifest.counts.models} models,
              {` ${manifest.counts.benchmarks} benchmarks, and ${manifest.counts.backends} backends: ${backendLabels}.`}
              Entity lists and observed combinations are derived from the data rather than fixed by the website.
            </p>
          </section>

          <section className="methodology-section" aria-labelledby="method-harnesses">
            <p className="eyebrow">Program generation</p>
            <h2 id="method-harnesses">Agent harnesses</h2>
            <p>
              The assigned harness and invoked provider model are recorded per model below. Where a Codex invocation
              used an explicit reasoning level, that setting is also retained in the model metadata. Command templates
              and the exact additional parameters are shown for each harness.
            </p>
            <div className="harness-list">
              {harnesses.map((harness) => (
                <article key={harness.id} className="harness-record">
                  <header>
                    <h3>{harness.label}</h3>
                    <span>{harness.models.length} {harness.models.length === 1 ? "model" : "models"}</span>
                  </header>
                  <code>{harness.commandTemplate}</code>
                  <p className="harness-models">
                    {harness.models.map((model) => (
                      <span key={model.id} title={modelInvocationTitle(model, harness.label)}>{model.label}</span>
                    ))}
                  </p>
                  <details className="harness-parameters">
                    <summary>Exact harness parameters</summary>
                    {harness.parameters.length > 0
                      ? <code>{harness.parameters.join(" ")}</code>
                      : <p>No additional harness parameters were passed.</p>}
                  </details>
                </article>
              ))}
              {modelsWithoutHarness.length > 0 && (
                <p className="method-note">
                  No harness metadata is recorded for {formatEntityList(modelsWithoutHarness.map((model) => model.label))}.
                  Their raw identifiers remain available in the data views.
                </p>
              )}
            </div>
            <p>
              The frozen invocation configuration is available in the pinned experiment script. Its recorded SHA-256
              digest is <code className="inline-digest">{experiment.sha256}</code>.
            </p>
          </section>

          <section className="methodology-section" aria-labelledby="method-validation">
            <p className="eyebrow">Validation</p>
            <h2 id="method-validation">Five sequential stages</h2>
            <p>A program reaches a stage only after passing every preceding stage.</p>
            <ol className="method-stage-list">
              <li><strong>Parallelization detection</strong><span>The generated source is inspected for constructs corresponding to the requested backend.</span></li>
              <li><strong>Build</strong><span>The staged source is configured and compiled.</span></li>
              <li><strong>Execution</strong><span>The executable is run with a benchmark-specific validation input and target-specific resources.</span></li>
              <li><strong>Internal validation</strong><span>The benchmark’s own correctness and sanity checks must pass.</span></li>
              <li><strong>Output comparison</strong><span>Exported results are compared with a known-good sequential reference.</span></li>
            </ol>
            <p>Only programs passing output comparison are eligible for performance benchmarking.</p>
          </section>

          <section className="methodology-section" aria-labelledby="method-system">
            <p className="eyebrow">Evaluation system</p>
            <h2 id="method-system">Recorded local execution system</h2>
            <p>
              Validation and performance measurements ran on host <code>{system.hostname}</code> with
              {` ${system.cpu.physicalCores} physical cores (${system.cpu.model}) across ${system.cpu.sockets} sockets and ${system.cpu.numaNodes} NUMA nodes.`}
              {` ${formatGpuInventory(system.gpus)} were available.`}
            </p>
            <div className="table-scroll methodology-resource-table">
              <table>
                <caption>Resource profiles used by validation and performance benchmarking</caption>
                <thead><tr><th scope="col">Phase</th><th scope="col">Backend</th><th scope="col">Effective resources</th></tr></thead>
                <tbody>
                  {system.resourceProfiles.map((profile) => (
                    <tr key={`${profile.phase}-${profile.backendId}`}>
                      <th scope="row">{profile.phase}</th>
                      <td>{backendLabel.get(profile.backendId) ?? profile.backendId}</td>
                      <td>{profile.description}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <details className="toolchain-record">
              <summary>Recorded toolchain</summary>
              <dl>
                <div><dt>Ruby</dt><dd>{system.toolchain.ruby}</dd></div>
                <div><dt>CMake</dt><dd>{system.toolchain.cmake}</dd></div>
                <div><dt>C</dt><dd>{system.toolchain.c}</dd></div>
                <div><dt>C++</dt><dd>{system.toolchain.cxx}</dd></div>
                <div><dt>CUDA</dt><dd>{system.toolchain.cuda}</dd></div>
                <div><dt>MPI</dt><dd>{system.toolchain.mpi}</dd></div>
              </dl>
            </details>
          </section>

          <section className="methodology-section" aria-labelledby="method-performance">
            <p className="eyebrow">Performance</p>
            <h2 id="method-performance">Cell-specific benchmark configuration</h2>
            <p>
              Each benchmark/backend cell has a reviewed and frozen problem size, resource allocation, and timeout.
              A benchmark attempt consists of one warm-up followed by five measured executions. The analysis uses
              the median of the five benchmark-reported computation times, expressed in milliseconds. Failed attempts
              remain explicit records and do not receive an imputed time.
            </p>
          </section>

          <section className="methodology-section" aria-labelledby="method-scoring">
            <p className="eyebrow">Scoring</p>
            <h2 id="method-scoring">Validation progress and relative performance</h2>
            <p>
              Every program receives an integer score from {manifest.scoreScale.minimum} to {manifest.scoreScale.maximum}.
              Scores 0–5 encode progress through validation and benchmarking. Scores 6–10 distinguish successful
              benchmark results within the complete benchmark/backend cell; filtering the website does not redefine
              these thresholds or the fastest run.
            </p>
            <div className="table-scroll methodology-score-table">
              <table>
                <caption className="sr-only">Meaning of each evaluation score</caption>
                <thead><tr><th scope="col">Score</th><th scope="col">Criterion</th></tr></thead>
                <tbody>
                  <tr><th scope="row">0</th><td>Requested parallelization was not detected.</td></tr>
                  <tr><th scope="row">1</th><td>Parallelization was detected; the build did not pass.</td></tr>
                  <tr><th scope="row">2</th><td>The build passed; validation execution did not pass.</td></tr>
                  <tr><th scope="row">3</th><td>Execution passed; internal validation did not pass.</td></tr>
                  <tr><th scope="row">4</th><td>Internal validation passed; output comparison did not pass.</td></tr>
                  <tr><th scope="row">5</th><td>Output comparison passed, but no successful performance result is available.</td></tr>
                  <tr><th scope="row">6</th><td>The benchmark completed outside the reviewed performance thresholds.</td></tr>
                  <tr><th scope="row">7–9</th><td>The median time met the cell’s reviewed good, great, or top threshold.</td></tr>
                  <tr><th scope="row">10</th><td>Fastest successful median time in the full benchmark/backend cell.</td></tr>
                </tbody>
              </table>
            </div>
            <p>
              Performance thresholds were derived from natural breaks in log median time, subject to a per-cell
              measurement-noise floor, then reviewed and frozen before scoring.
            </p>
          </section>
        </div>

        <aside className="methodology-references" aria-label="Methodology records">
          <section>
            <p className="eyebrow">Scope</p>
            <h2>Current dataset</h2>
            <p>This is an ongoing evaluation. The figures report the retained observations in the identified snapshot; they do not estimate missing combinations as zero.</p>
          </section>
          <section>
            <p className="eyebrow">Primary records</p>
            <h2>Repository sources</h2>
            <div className="reference-links">
              <a href={`${artifactRoot}/method`} target="_blank" rel="noreferrer"><span>Pipeline source snapshot</span><strong>GitHub ↗</strong></a>
              <a href={experimentUrl} target="_blank" rel="noreferrer"><span>Experiment harness configuration</span><strong>GitHub ↗</strong></a>
              <a href={`${artifactBlob}/data/provenance/system.md`} target="_blank" rel="noreferrer"><span>Execution-system record</span><strong>GitHub ↗</strong></a>
              <a href={`${artifactBlob}/data/calibration/benchmark_config.yaml`} target="_blank" rel="noreferrer"><span>Benchmark configuration</span><strong>GitHub ↗</strong></a>
              <a href={`${artifactBlob}/data/scoring/local_scoring_threshold_review.yaml`} target="_blank" rel="noreferrer"><span>Threshold review</span><strong>GitHub ↗</strong></a>
              <a href={`${artifactBlob}/data/scoring/scoring_metadata.yaml`} target="_blank" rel="noreferrer"><span>Scoring metadata</span><strong>GitHub ↗</strong></a>
              <a href={`${manifest.generatedSourceRepository}/tree/${manifest.generatedSourceCommit}`} target="_blank" rel="noreferrer"><span>Generated programs</span><strong>GitHub ↗</strong></a>
            </div>
          </section>
        </aside>
      </div>
    </main>
  );
}
