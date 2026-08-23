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

export const datasetManifestSchema = z.object({
  schemaVersion: z.literal(1),
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
  benchmarks: z.array(entitySchema),
  backends: z.array(entitySchema),
  methodology: methodologySchema,
  cells: z.array(cellSchema),
  scoreCubePath: z.string().min(1),
  runIndexPath: z.string().min(1),
});

export const scoreCubeSchema = z.array(z.object({
  modelId: z.string().min(1),
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
  score: z.number().int(),
  count: z.number().int().positive(),
}));

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
  validationEvidenceUrl: z.string().url(),
  benchmarkEvidenceUrl: z.string().url().nullable(),
});

export const runShardSchema = z.array(runRecordSchema);

export const runIndexSchema = z.record(z.string(), z.object({
  benchmarkId: z.string().min(1),
  backendId: z.string().min(1),
}));
