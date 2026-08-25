import { z } from "zod";

export const scoreBandSchema = z.object({
  id: z.string().min(1),
  label: z.string().min(1),
  detail: z.string().min(1),
  minimum: z.number().int(),
  maximum: z.number().int(),
  color: z.string().min(1),
});

const entitySchema = z.object({
  id: z.string().min(1),
  label: z.string().min(1),
});

const modelInvocationSchema = z.object({
  harnessId: z.string().min(1),
  invokedModelId: z.string().min(1),
  reasoningEffort: z.string().min(1).nullable(),
});

const modelSchema = entitySchema.extend({
  invocation: modelInvocationSchema.nullable(),
});

const modelSetSchema = entitySchema.extend({
  modelIds: z.array(z.string().min(1)).min(1),
});

const harnessSchema = z.object({
  id: z.string().min(1),
  label: z.string().min(1),
  commandTemplate: z.string().min(1),
  parameters: z.array(z.string().min(1)),
});

const methodologySchema = z.object({
  experimentScript: z.object({
    repository: z.string().url(),
    commit: z.string().regex(/^[0-9a-f]{40}$/),
    path: z.string().min(1),
    sha256: z.string().regex(/^[0-9a-f]{64}$/),
  }),
  harnesses: z.array(harnessSchema).min(1),
  executionSystem: z.object({
    hostname: z.string().min(1),
    cpu: z.object({
      model: z.string().min(1),
      physicalCores: z.number().int().positive(),
      sockets: z.number().int().positive(),
      numaNodes: z.number().int().positive(),
    }),
    gpus: z.array(z.object({
      index: z.number().int().nonnegative(),
      model: z.string().min(1),
      memoryMiB: z.number().int().positive(),
    })),
    toolchain: z.object({
      ruby: z.string().min(1),
      cmake: z.string().min(1),
      c: z.string().min(1),
      cxx: z.string().min(1),
      cuda: z.string().min(1),
      mpi: z.string().min(1),
    }),
    resourceProfiles: z.array(z.object({
      phase: z.string().min(1),
      backendId: z.string().min(1),
      description: z.string().min(1),
    })).min(1),
  }),
});

const thresholdsSchema = z.object({
  fastestMs: z.number().positive(),
  topMs: z.number().positive(),
  greatMs: z.number().positive(),
  goodMs: z.number().positive(),
});

const cellSchema = z.object({
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
  runCount: z.number().int().nonnegative(),
  successfulRunCount: z.number().int().nonnegative(),
  shardPath: z.string().min(1),
  thresholds: thresholdsSchema.nullable(),
});

const performanceCellSelectionSchema = z.object({
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
});

const costDatasetDescriptorSchema = z.object({
  datasetPath: z.string().min(1),
  pricingAsOf: z.iso.date(),
  sourcePath: z.string().min(1),
  sourceDigest: z.string().regex(/^[0-9a-f]{64}$/),
  selectionPolicy: z.string().min(1),
});

export const datasetManifestSchema = z.object({
  schemaVersion: z.literal(2),
  title: z.string().min(1),
  subtitle: z.string().min(1),
  artifactRepository: z.string().url(),
  artifactCommit: z.string().regex(/^[0-9a-f]{40}$/),
  scoringDigest: z.string().regex(/^[0-9a-f]{64}$/),
  dataGeneratedAt: z.string().min(1),
  generatedSourceRepository: z.string().url(),
  generatedSourceCommit: z.string().regex(/^[0-9a-f]{40}$/),
  scoreScale: z.object({
    minimum: z.number().int(),
    maximum: z.number().int(),
    bands: z.array(scoreBandSchema).min(1),
  }),
  counts: z.object({
    runs: z.number().int().nonnegative(),
    models: z.number().int().nonnegative(),
    benchmarks: z.number().int().nonnegative(),
    backends: z.number().int().nonnegative(),
  }),
  models: z.array(modelSchema),
  modelSets: z.array(modelSetSchema),
  defaultModelSetId: z.string().min(1).nullable(),
  defaultPerformanceCell: performanceCellSelectionSchema.nullable(),
  benchmarks: z.array(entitySchema),
  backends: z.array(entitySchema),
  methodology: methodologySchema,
  cost: costDatasetDescriptorSchema,
  cells: z.array(cellSchema),
  scoreCubePath: z.string().min(1),
  runIndexPath: z.string().min(1),
}).superRefine((manifest, context) => {
  const knownModels = new Set(manifest.models.map((model) => model.id));
  const knownModelSets = new Set<string>();
  manifest.modelSets.forEach((modelSet, setIndex) => {
    if (knownModelSets.has(modelSet.id)) {
      context.addIssue({ code: "custom", message: `duplicate model set: ${modelSet.id}`, path: ["modelSets", setIndex, "id"] });
    }
    knownModelSets.add(modelSet.id);
    const members = new Set<string>();
    modelSet.modelIds.forEach((modelId, modelIndex) => {
      if (!knownModels.has(modelId)) {
        context.addIssue({ code: "custom", message: `unknown model in set: ${modelId}`, path: ["modelSets", setIndex, "modelIds", modelIndex] });
      }
      if (members.has(modelId)) {
        context.addIssue({ code: "custom", message: `duplicate model in set: ${modelId}`, path: ["modelSets", setIndex, "modelIds", modelIndex] });
      }
      members.add(modelId);
    });
  });
  if (manifest.defaultModelSetId !== null && !knownModelSets.has(manifest.defaultModelSetId)) {
    context.addIssue({ code: "custom", message: `unknown default model set: ${manifest.defaultModelSetId}`, path: ["defaultModelSetId"] });
  }
  if (manifest.defaultPerformanceCell !== null && !manifest.cells.some((cell) =>
    cell.benchmarkId === manifest.defaultPerformanceCell?.benchmarkId
    && cell.backendId === manifest.defaultPerformanceCell?.backendId)) {
    context.addIssue({
      code: "custom",
      message: `unknown default performance cell: ${manifest.defaultPerformanceCell.benchmarkId}/${manifest.defaultPerformanceCell.backendId}`,
      path: ["defaultPerformanceCell"],
    });
  }
});

export const scoreCubeSchema = z.array(z.object({
  modelId: z.string().min(1),
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
  score: z.number().int(),
  count: z.number().int().positive(),
}));

const timingCorrectionSourceSchema = z.object({
  commit: z.string().regex(/^[0-9a-f]{40}$/),
  digest: z.string().regex(/^[0-9a-f]{64}$/),
  url: z.string().url(),
});

export const runRecordSchema = z.object({
  id: z.string().min(1),
  modelId: z.string().min(1),
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
  repetition: z.number().int().positive(),
  overallScore: z.number().int(),
  scoreBandId: z.string().min(1),
  validationStatus: z.number().int().nonnegative(),
  validationMessage: z.string(),
  validationStages: z.record(z.string(), z.boolean().nullable()),
  benchmarkSuccess: z.boolean().nullable(),
  benchmarkMedianMs: z.number().positive().nullable(),
  benchmarkMeasurementsMs: z.array(z.number().positive()),
  sourceBatch: z.string().min(1),
  sourcePath: z.string().min(1),
  sourceUrl: z.string().url(),
  timingFixed: z.boolean(),
  timingCorrection: z.object({
    issueCategories: z.array(z.string().min(1)).min(1),
    originalSource: timingCorrectionSourceSchema,
    correctedSource: timingCorrectionSourceSchema,
  }).nullable(),
  validationEvidenceUrl: z.string().url(),
  benchmarkEvidenceUrl: z.string().url().nullable(),
}).superRefine((run, context) => {
  if (run.timingFixed !== (run.timingCorrection !== null)) {
    context.addIssue({ code: "custom", message: "timing correction flag/payload mismatch", path: ["timingCorrection"] });
  }
  if (run.timingCorrection !== null && run.sourceUrl !== run.timingCorrection.correctedSource.url) {
    context.addIssue({ code: "custom", message: "effective source URL is not the corrected source", path: ["sourceUrl"] });
  }
});

export const runShardSchema = z.array(runRecordSchema);

export const runIndexSchema = z.record(z.string(), z.object({
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
}));

export const costPricingProfileSchema = z.object({
  id: z.string().min(1),
  modelLabel: z.string().min(1),
  inputPriceUsdPerMillion: z.number().nonnegative(),
  cachedInputPriceUsdPerMillion: z.number().nonnegative(),
  outputPriceUsdPerMillion: z.number().nonnegative(),
  effectivePriceUsdPerMillion: z.number().positive().nullable(),
  pricingAsOf: z.iso.date(),
  pricingModelId: z.string().min(1),
  pricingProvider: z.string().min(1),
  pricingProviderTag: z.string().min(1),
  pricingQuantization: z.string().min(1),
  pricingSourceKind: z.string().min(1),
  pricingSelectionPolicy: z.string().min(1),
  pricingCatalogUrl: z.string().url(),
  pricingEndpointUrl: z.string().url().nullable(),
  pricingSourceUrl: z.string().url(),
  secondaryPricingSourceUrl: z.string().url().nullable(),
  pricingMatchNote: z.string().min(1),
  costMethod: z.string().min(1),
});

export const costRunRecordSchema = z.object({
  id: z.string().min(1),
  modelId: z.string().min(1),
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
  repetition: z.number().int().positive(),
  overallScore: z.number().int(),
  pricingProfileId: z.string().min(1).nullable(),
  inputTokens: z.number().int().nonnegative().nullable(),
  cachedInputTokens: z.number().int().nonnegative().nullable(),
  outputTokens: z.number().int().nonnegative().nullable(),
  totalTokens: z.number().int().nonnegative().nullable(),
  estimatedCostUsd: z.number().nonnegative().nullable(),
});

export const costDatasetSchema = z.object({
  schemaVersion: z.literal(1),
  pricingAsOf: z.iso.date(),
  sourceDigest: z.string().regex(/^[0-9a-f]{64}$/),
  profiles: z.array(costPricingProfileSchema).min(1),
  aliases: z.record(z.string().min(1), z.string().min(1)),
  inputTokenAccounting: z.record(z.string().min(1), z.enum(["includes-cached", "excludes-cached"])),
  runs: z.array(costRunRecordSchema),
}).superRefine((dataset, context) => {
  const profiles = new Set<string>();
  dataset.profiles.forEach((profile, index) => {
    if (profiles.has(profile.id)) {
      context.addIssue({ code: "custom", message: `duplicate cost profile: ${profile.id}`, path: ["profiles", index, "id"] });
    }
    profiles.add(profile.id);
    if (profile.pricingAsOf !== dataset.pricingAsOf) {
      context.addIssue({ code: "custom", message: `inconsistent pricing date: ${profile.id}`, path: ["profiles", index, "pricingAsOf"] });
    }
  });
  Object.entries(dataset.aliases).forEach(([modelId, profileId]) => {
    if (!profiles.has(profileId)) {
      context.addIssue({ code: "custom", message: `unknown aliased cost profile: ${profileId}`, path: ["aliases", modelId] });
    }
  });
  const knownCostModels = new Set<string>([
    ...dataset.profiles.map((profile) => profile.id),
    ...Object.keys(dataset.aliases),
    ...dataset.runs.map((run) => run.modelId),
  ]);
  Object.keys(dataset.inputTokenAccounting).forEach((modelId) => {
    if (!knownCostModels.has(modelId)) {
      context.addIssue({ code: "custom", message: `unknown input-token accounting model: ${modelId}`, path: ["inputTokenAccounting", modelId] });
    }
  });
  const runIds = new Set<string>();
  dataset.runs.forEach((run, index) => {
    if (runIds.has(run.id)) {
      context.addIssue({ code: "custom", message: `duplicate cost run: ${run.id}`, path: ["runs", index, "id"] });
    }
    runIds.add(run.id);
    if (run.pricingProfileId !== null && !profiles.has(run.pricingProfileId)) {
      context.addIssue({ code: "custom", message: `unknown run cost profile: ${run.pricingProfileId}`, path: ["runs", index, "pricingProfileId"] });
    }
    const expectedProfileId = profiles.has(run.modelId) ? run.modelId : dataset.aliases[run.modelId] ?? null;
    if (run.pricingProfileId !== expectedProfileId) {
      context.addIssue({ code: "custom", message: `run pricing profile disagrees with model policy: ${run.id}`, path: ["runs", index, "pricingProfileId"] });
    }
    if ((dataset.inputTokenAccounting[run.modelId] ?? "includes-cached") === "includes-cached"
      && run.cachedInputTokens !== null && run.inputTokens !== null && run.cachedInputTokens > run.inputTokens) {
      context.addIssue({ code: "custom", message: "cached tokens exceed input tokens", path: ["runs", index, "cachedInputTokens"] });
    }
    if (run.estimatedCostUsd !== null && run.pricingProfileId === null) {
      context.addIssue({ code: "custom", message: "estimated cost lacks a pricing profile", path: ["runs", index, "estimatedCostUsd"] });
    }
  });
});
