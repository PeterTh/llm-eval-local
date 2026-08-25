import { describe, expect, it } from "vitest";

import { costDatasetFixture, manifestFixture, runsFixture, scoreCubeFixture } from "../test/fixtures";
import { costDatasetSchema, datasetManifestSchema, runShardSchema, scoreCubeSchema } from "./schema";

describe("runtime dataset validation", () => {
  it("accepts the stable public interfaces", () => {
    expect(datasetManifestSchema.parse(manifestFixture)).toEqual(manifestFixture);
    expect(scoreCubeSchema.parse(scoreCubeFixture)).toEqual(scoreCubeFixture);
    expect(runShardSchema.parse(runsFixture)).toEqual(runsFixture);
    expect(costDatasetSchema.parse(costDatasetFixture)).toEqual(costDatasetFixture);
  });

  it("rejects malformed performance metrics and provenance", () => {
    expect(() => runShardSchema.parse([{ ...runsFixture[1], benchmarkMedianMs: -1 }])).toThrow();
    expect(() => runShardSchema.parse([{ ...runsFixture[1], sourceUrl: "relative/path" }])).toThrow();
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
