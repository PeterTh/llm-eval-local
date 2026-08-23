import { describe, expect, it } from "vitest";

import { manifestFixture, runsFixture, scoreCubeFixture } from "../test/fixtures";
import { datasetManifestSchema, runShardSchema, scoreCubeSchema } from "./schema";

describe("runtime dataset validation", () => {
  it("accepts the stable public interfaces", () => {
    expect(datasetManifestSchema.parse(manifestFixture)).toEqual(manifestFixture);
    expect(scoreCubeSchema.parse(scoreCubeFixture)).toEqual(scoreCubeFixture);
    expect(runShardSchema.parse(runsFixture)).toEqual(runsFixture);
  });

  it("rejects malformed performance metrics and provenance", () => {
    expect(() => runShardSchema.parse([{ ...runsFixture[1], benchmarkMedianMs: -1 }])).toThrow();
    expect(() => runShardSchema.parse([{ ...runsFixture[1], sourceUrl: "relative/path" }])).toThrow();
    expect(() => datasetManifestSchema.parse({
      ...manifestFixture,
      models: [{ ...manifestFixture.models[0], invocation: { ...manifestFixture.models[0]!.invocation!, harnessId: "" } }],
    })).toThrow();
    expect(() => datasetManifestSchema.parse({ ...manifestFixture, defaultModelSetId: "missing" })).toThrow();
    expect(() => datasetManifestSchema.parse({
      ...manifestFixture,
      modelSets: [{ ...manifestFixture.modelSets[0], modelIds: ["missing-model"] }],
    })).toThrow();
  });
});
