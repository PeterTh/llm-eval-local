import type { DatasetManifest, RunRecord, ScoreCubeCell } from "../data/types";

export const manifestFixture: DatasetManifest = {
  schemaVersion: 1,
  title: "Test evaluation",
  subtitle: "Synthetic fixture",
  artifactRepository: "https://github.com/example/artifact",
  artifactCommit: "a".repeat(40),
  scoringDigest: "b".repeat(64),
  dataGeneratedAt: "2026-08-23T00:00:00Z",
  generatedSourceRepository: "https://github.com/example/generated",
  generatedSourceCommit: "c".repeat(40),
  scoreScale: {
    minimum: 0,
    maximum: 10,
    bands: [
      { id: "invalid", label: "Invalid", detail: "Scores 0–4", minimum: 0, maximum: 4, color: "#c73b46" },
      { id: "no-speedup", label: "No Speedup", detail: "Score 5", minimum: 5, maximum: 5, color: "#d9822b" },
      { id: "ok", label: "OK", detail: "Scores 6–7", minimum: 6, maximum: 7, color: "#3978a8" },
      { id: "good-top", label: "Good–Top", detail: "Scores 8–10", minimum: 8, maximum: 10, color: "#36835a" },
    ],
  },
  counts: { runs: 3, models: 2, benchmarks: 2, backends: 2 },
  models: [
    {
      id: "model/a?x", label: "Model A",
      invocation: { harnessId: "copilot-cli", invokedModelId: "provider/model-a", reasoningEffort: null },
    },
    { id: "unknown-model", label: "unknown-model", invocation: null },
  ],
  benchmarks: [{ id: "bench&one", label: "Bench & One" }, { id: "missing-cell", label: "missing-cell" }],
  backends: [{ id: "gpu+x", label: "GPU + X" }, { id: "cpu", label: "cpu" }],
  methodology: {
    experimentScript: {
      repository: "https://github.com/example/experiment",
      commit: "d".repeat(40),
      path: "experiment.rb",
      sha256: "e".repeat(64),
    },
    harnesses: [{
      id: "copilot-cli",
      label: "GitHub Copilot CLI",
      commandTemplate: "copilot [parameters] --model <model> -p <instruction>",
      parameters: ["--autopilot"],
    }],
    executionSystem: {
      hostname: "test-host",
      cpu: { model: "Test CPU", physicalCores: 8, sockets: 1, numaNodes: 1 },
      gpus: [{ index: 0, model: "Test GPU", memoryMiB: 1024 }],
      toolchain: {
        ruby: "ruby test", cmake: "cmake test", c: "cc test", cxx: "cxx test", cuda: "cuda test", mpi: "mpi test",
      },
      resourceProfiles: [
        { phase: "validation", backendId: "gpu+x", description: "one test GPU" },
        { phase: "benchmark", backendId: "gpu+x", description: "one test GPU" },
      ],
    },
  },
  cells: [{
    benchmarkId: "bench&one", backendId: "gpu+x", runCount: 3, successfulRunCount: 1,
    shardPath: "data/runs-test.json", thresholds: { fastestMs: 10, topMs: 12, greatMs: 15, goodMs: 20 },
  }],
  scoreCubePath: "data/score-cube-test.json",
  runIndexPath: "data/run-index-test.json",
};

export const scoreCubeFixture: ScoreCubeCell[] = [
  { modelId: "model/a?x", benchmarkId: "bench&one", backendId: "gpu+x", score: 4, count: 1 },
  { modelId: "model/a?x", benchmarkId: "bench&one", backendId: "gpu+x", score: 8, count: 1 },
  { modelId: "unknown-model", benchmarkId: "bench&one", backendId: "gpu+x", score: 10, count: 1 },
];

export const runsFixture: RunRecord[] = [
  {
    id: "bench&one_model/a?x_gpu+x_r1", modelId: "model/a?x", benchmarkId: "bench&one", backendId: "gpu+x",
    repetition: 1, overallScore: 4, scoreBandId: "invalid", validationStatus: 2, validationMessage: "compile failed",
    validationStages: { build: false, run: null }, benchmarkSuccess: null, benchmarkMedianMs: null, benchmarkMeasurementsMs: [],
    sourceBatch: "batch", sourcePath: "batch/result one", sourceUrl: "https://github.com/example/generated/tree/cccc/result%20one",
    validationEvidenceUrl: "https://github.com/example/artifact/blob/aaaa/validation.jsonl#L1", benchmarkEvidenceUrl: null,
  },
  {
    id: "bench&one_model/a?x_gpu+x_r2", modelId: "model/a?x", benchmarkId: "bench&one", backendId: "gpu+x",
    repetition: 2, overallScore: 8, scoreBandId: "good-top", validationStatus: 5, validationMessage: "",
    validationStages: { build: true, run: true }, benchmarkSuccess: true, benchmarkMedianMs: 10, benchmarkMeasurementsMs: [9, 10, 10, 11, 10],
    sourceBatch: "batch", sourcePath: "batch/result two", sourceUrl: "https://github.com/example/generated/tree/cccc/result%20two",
    validationEvidenceUrl: "https://github.com/example/artifact/blob/aaaa/validation.jsonl#L2",
    benchmarkEvidenceUrl: "https://github.com/example/artifact/blob/aaaa/benchmark.jsonl#L1",
  },
  {
    id: "bench&one_unknown-model_gpu+x_r1", modelId: "unknown-model", benchmarkId: "bench&one", backendId: "gpu+x",
    repetition: 1, overallScore: 10, scoreBandId: "good-top", validationStatus: 5, validationMessage: "",
    validationStages: { build: true, run: true }, benchmarkSuccess: false, benchmarkMedianMs: null, benchmarkMeasurementsMs: [],
    sourceBatch: "batch", sourcePath: "batch/result three", sourceUrl: "https://github.com/example/generated/tree/cccc/result%20three",
    validationEvidenceUrl: "https://github.com/example/artifact/blob/aaaa/validation.jsonl#L3",
    benchmarkEvidenceUrl: "https://github.com/example/artifact/blob/aaaa/benchmark.jsonl#L2",
  },
];
