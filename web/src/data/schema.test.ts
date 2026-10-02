import { describe, expect, it } from "vitest";

import { costDatasetFixture, manifestFixture, runsFixture, scoreCubeFixture } from "../test/fixtures";
import { costDatasetSchema, datasetManifestSchema, runShardSchema, scoreCubeSchema } from "./schema";

describe("runtime dataset validation", () => {
  it("retains the complete correction history and explicit failed revalidation", () => {
    const run = structuredClone(runsFixture[1]!);
    run.timingCorrection!.intermediateSources = [run.timingCorrection!.originalSource];
    run.originalValidationEvidenceUrl = run.validationEvidenceUrl;
    expect(runShardSchema.parse([run])[0]).toEqual(run);
    run.validationDisposition = { classification: "pre_existing_correctness_failure", reason: "Independent review confirms a pre-existing race." };
    expect(() => runShardSchema.parse([run])).toThrow();
    run.validationStatus = 4;
    run.overallScore = 4;
    run.benchmarkSuccess = null;
    run.benchmarkMedianMs = null;
    run.benchmarkMeasurementsMs = [];
    expect(runShardSchema.parse([run])[0]).toEqual(run);
  });
  it("preserves per-profile dates and requires the dataset date to be their maximum", () => {
    const dataset = structuredClone(costDatasetFixture);
    dataset.pricingAsOf = "2026-09-29";
    dataset.profiles.push({ ...dataset.profiles[0]!, id: "new-profile", pricingAsOf: "2026-09-29" });
    expect(() => costDatasetSchema.parse(dataset)).not.toThrow();
    expect(() => costDatasetSchema.parse({ ...dataset, pricingAsOf: "2026-08-22" })).toThrow();
    expect(() => costDatasetSchema.parse({ ...dataset, pricingAsOf: "2026-09-30" })).toThrow();
  });
  it("accepts the stable public interfaces", () => {
    expect(datasetManifestSchema.parse(manifestFixture)).toEqual(manifestFixture);
    expect(scoreCubeSchema.parse(scoreCubeFixture)).toEqual(scoreCubeFixture);
    expect(runShardSchema.parse(runsFixture)).toEqual(runsFixture);
    expect(costDatasetSchema.parse(costDatasetFixture)).toEqual(costDatasetFixture);
  });

  it("rejects malformed performance metrics and provenance", () => {
    expect(() => runShardSchema.parse([{ ...runsFixture[1], benchmarkMedianMs: -1 }])).toThrow();
    expect(() => runShardSchema.parse([{ ...runsFixture[1], sourceUrl: "relative/path" }])).toThrow();
    expect(() => runShardSchema.parse([{ ...runsFixture[0], implementationAnalysisMarkdown: "" }])).toThrow();
    expect(() => runShardSchema.parse([{ ...runsFixture[0], implementationAnalysisMarkdown: undefined }])).toThrow();
    expect(() => runShardSchema.parse([{ ...runsFixture[1], timingFixed: false }])).toThrow();
    expect(() => runShardSchema.parse([{ ...runsFixture[1], sourceUrl: runsFixture[1]!.timingCorrection!.originalSource.url }])).toThrow();
    expect(() => datasetManifestSchema.parse({
      ...manifestFixture,
      models: [{ ...manifestFixture.models[0], invocation: { ...manifestFixture.models[0]!.invocation!, harnessId: "" } }],
    })).toThrow();
    expect(() => costDatasetSchema.parse({
      ...costDatasetFixture,
      aliases: { "model/a?x": "missing-profile" },
    })).toThrow();
    expect(() => costDatasetSchema.parse({ ...costDatasetFixture, sourceDigest: "not-a-digest" })).toThrow();
    expect(() => costDatasetSchema.parse({
      ...costDatasetFixture,
      runs: [{ ...costDatasetFixture.runs[0], cachedInputTokens: 101 }],
    })).toThrow();
    expect(() => datasetManifestSchema.parse({ ...manifestFixture, defaultModelSetId: "missing" })).toThrow();
    expect(() => datasetManifestSchema.parse({
      ...manifestFixture,
      defaultPerformanceCell: { benchmarkId: "missing-cell", backendId: "cpu" },
    })).toThrow();
    expect(() => datasetManifestSchema.parse({
      ...manifestFixture,
      modelSets: [{ ...manifestFixture.modelSets[0], modelIds: ["missing-model"] }],
    })).toThrow();
  });
});
