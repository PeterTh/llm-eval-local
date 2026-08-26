export interface ScoreBand {
  id: string;
  label: string;
  detail: string;
  minimum: number;
  maximum: number;
  color: string;
}

export interface EntityMetadata {
  id: string;
  label: string;
}

export interface ModelInvocationMetadata {
  harnessId: string;
  invokedModelId: string;
  reasoningEffort: string | null;
}

export interface ModelMetadata extends EntityMetadata {
  invocation: ModelInvocationMetadata | null;
}

export interface ModelSetMetadata extends EntityMetadata {
  modelIds: string[];
}

export interface HarnessMetadata {
  id: string;
  label: string;
  commandTemplate: string;
  parameters: string[];
}

export interface ExecutionSystemMetadata {
  hostname: string;
  cpu: {
    model: string;
    physicalCores: number;
    sockets: number;
    numaNodes: number;
  };
  gpus: Array<{
    index: number;
    model: string;
    memoryMiB: number;
  }>;
  toolchain: {
    ruby: string;
    cmake: string;
    c: string;
    cxx: string;
    cuda: string;
    mpi: string;
  };
  resourceProfiles: Array<{
    phase: string;
    backendId: string;
    description: string;
  }>;
}

export interface MethodologyMetadata {
  experimentScript: {
    repository: string;
    commit: string;
    path: string;
    sha256: string;
  };
  harnesses: HarnessMetadata[];
  executionSystem: ExecutionSystemMetadata;
}

export interface PerformanceThresholds {
  fastestMs: number;
  topMs: number;
  greatMs: number;
  goodMs: number;
}

export interface CellDescriptor {
  benchmarkId: string;
  backendId: string;
  runCount: number;
  successfulRunCount: number;
  shardPath: string;
  thresholds: PerformanceThresholds | null;
}

export interface PerformanceCellSelection {
  benchmarkId: string;
  backendId: string;
}

export interface CostDatasetDescriptor {
  datasetPath: string;
  pricingAsOf: string;
  sourcePath: string;
  sourceDigest: string;
  selectionPolicy: string;
}

export interface CostPricingProfile {
  id: string;
  modelLabel: string;
  inputPriceUsdPerMillion: number;
  cachedInputPriceUsdPerMillion: number;
  outputPriceUsdPerMillion: number;
  effectivePriceUsdPerMillion: number | null;
  pricingAsOf: string;
  pricingModelId: string;
  pricingProvider: string;
  pricingProviderTag: string;
  pricingQuantization: string;
  pricingSourceKind: string;
  pricingSelectionPolicy: string;
  pricingCatalogUrl: string;
  pricingEndpointUrl: string | null;
  pricingSourceUrl: string;
  secondaryPricingSourceUrl: string | null;
  pricingMatchNote: string;
  costMethod: string;
}

export interface CostRunRecord {
  id: string;
  modelId: string;
  benchmarkId: string;
  backendId: string;
  repetition: number;
  overallScore: number;
  pricingProfileId: string | null;
  inputTokens: number | null;
  cachedInputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  estimatedCostUsd: number | null;
}

export interface CostDataset {
  schemaVersion: 1;
  pricingAsOf: string;
  sourceDigest: string;
  profiles: CostPricingProfile[];
  aliases: Record<string, string>;
  inputTokenAccounting: Record<string, "includes-cached" | "excludes-cached">;
  runs: CostRunRecord[];
}

export interface DatasetManifest {
  schemaVersion: 2;
  title: string;
  subtitle: string;
  artifactRepository: string;
  artifactCommit: string;
  scoringDigest: string;
  dataGeneratedAt: string;
  generatedSourceRepository: string;
  generatedSourceCommit: string;
  scoreScale: {
    minimum: number;
    maximum: number;
    bands: ScoreBand[];
  };
  counts: {
    runs: number;
    models: number;
    benchmarks: number;
    backends: number;
  };
  models: ModelMetadata[];
  modelSets: ModelSetMetadata[];
  defaultModelSetId: string | null;
  defaultPerformanceCell: PerformanceCellSelection | null;
  benchmarks: EntityMetadata[];
  backends: EntityMetadata[];
  methodology: MethodologyMetadata;
  cost: CostDatasetDescriptor;
  cells: CellDescriptor[];
  scoreCubePath: string;
  runIndexPath: string;
}

export interface RunIndexEntry {
  benchmarkId: string;
  backendId: string;
}

export interface ScoreCubeCell {
  modelId: string;
  benchmarkId: string;
  backendId: string;
  score: number;
  count: number;
}

export interface TimingCorrectionSource {
  commit: string;
  digest: string;
  url: string;
}

export interface TimingCorrectionProvenance {
  issueCategories: string[];
  originalSource: TimingCorrectionSource;
  correctedSource: TimingCorrectionSource;
}

export interface RunRecord {
  id: string;
  modelId: string;
  benchmarkId: string;
  backendId: string;
  repetition: number;
  overallScore: number;
  scoreBandId: string;
  validationStatus: number;
  validationMessage: string;
  validationStages: Record<string, boolean | null>;
  benchmarkSuccess: boolean | null;
  benchmarkMedianMs: number | null;
  benchmarkMeasurementsMs: number[];
  implementationAnalysisMarkdown: string | null;
  sourceBatch: string;
  sourcePath: string;
  sourceUrl: string;
  timingFixed: boolean;
  timingCorrection: TimingCorrectionProvenance | null;
  validationEvidenceUrl: string;
  benchmarkEvidenceUrl: string | null;
}

export type SortOrder = "weakest" | "strongest" | "alphabetical";

export interface FilterState {
  models: string[];
  benchmarks: string[];
  backends: string[];
  scoreBands: string[];
  outcome: "all" | "successful" | "failed" | "unavailable";
  sort: SortOrder;
  scale: "log" | "linear";
  performanceMode: "absolute" | "relative";
}
