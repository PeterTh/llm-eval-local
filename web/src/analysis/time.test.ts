import { describe, expect, it } from "vitest";
import { manifestFixture, timeDatasetFixture } from "../test/fixtures";
import { analyzeTime, timeDomain } from "./time";

const all = { models: [], benchmarks: [], backends: [] };

describe("generation-time analysis", () => {
  it("includes failed outcomes and weights individual runs, keeping timing coverage separate", () => {
    const dataset = { ...timeDatasetFixture, runs: timeDatasetFixture.runs.map((run, index) => index === 1 ? { ...run, generationTimeSeconds: null } : run) };
    const result = analyzeTime(dataset, manifestFixture, { ...all, models: ["model/a?x"], benchmarks: ["bench&one"], backends: ["gpu+x"] });
    expect(result).toMatchObject({ scoreRunCount: 2, timeRunCount: 1, unavailableTimeRunCount: 1 });
    expect(result.models[0]).toMatchObject({ meanScore: 6, meanGenerationTimeSeconds: 60, distribution: { mean: 60, median: 60, minimum: 60, maximum: 60, outlierCount: 0 } });
    expect(analyzeTime(timeDatasetFixture, manifestFixture, all).models[0]).toMatchObject({ modelId: "unknown-model", meanGenerationTimeSeconds: 300 });
  });
  it("computes Tukey statistics in seconds and preserves long outliers", () => {
    const base = timeDatasetFixture.runs[0]!;
    const dataset = { ...timeDatasetFixture, runs: [60, 120, 180, 240, 300, 3600].map((seconds, index) => ({ ...base, id: `run-${index}`, repetition: index + 1, generationTimeSeconds: seconds })) };
    const result = analyzeTime(dataset, manifestFixture, all).models[0]!;
    expect(result.distribution).toEqual({ count: 6, mean: 750, median: 210, firstQuartile: 135, thirdQuartile: 285, lowerWhisker: 60, upperWhisker: 300, outlierCount: 1, minimum: 60, maximum: 3600 });
    expect(result.outliers.map((run) => run.id)).toEqual(["run-5"]);
  });
  it("exposes unavailable models without inventing zero time", () => {
    const dataset = { ...timeDatasetFixture, runs: timeDatasetFixture.runs.map((run) => ({ ...run, generationTimeSeconds: null })) };
    const result = analyzeTime(dataset, manifestFixture, all);
    expect(result.plottedModels).toEqual([]);
    expect(result.models).toHaveLength(2);
    expect(result.models[0]).toMatchObject({ meanGenerationTimeSeconds: null, distribution: null, outliers: [] });
    expect(result.unavailableTimeRunCount).toBe(3);
  });
  it("filters every dimension and orders tied means by label", () => {
    for (const key of ["models", "benchmarks", "backends"] as const) {
      expect(analyzeTime(timeDatasetFixture, manifestFixture, { ...all, [key]: ["missing"] }).models).toEqual([]);
    }
    const dataset = { ...timeDatasetFixture, runs: timeDatasetFixture.runs.map((run) => ({ ...run, generationTimeSeconds: 60 })) };
    expect(analyzeTime(dataset, manifestFixture, all).models.map((model) => model.modelId)).toEqual(["model/a?x", "unknown-model"]);
  });
  it("keeps unbalanced cell means weighted by observations", () => {
    const base = timeDatasetFixture.runs[0]!;
    const dataset = { ...timeDatasetFixture, runs: [
      { ...base, id: "a", generationTimeSeconds: 60, overallScore: 0 },
      { ...base, id: "b", generationTimeSeconds: 60, overallScore: 0 },
      { ...base, id: "c", benchmarkId: "another", generationTimeSeconds: 600, overallScore: 9 },
    ] };
    expect(analyzeTime(dataset, manifestFixture, all).models[0]).toMatchObject({ meanGenerationTimeSeconds: 240, meanScore: 3 });
  });
  it("handles empty, singleton, linear and log domains without clipping extremes", () => {
    expect(timeDomain([], "linear")).toEqual([0, 60]);
    expect(timeDomain([], "log")).toEqual([1, 60]);
    expect(timeDomain([60], "log")).toEqual([40, 90]);
    expect(timeDomain([60, 3600], "linear")[0]).toBe(0);
    expect(timeDomain([60, 3600], "linear")[1]).toBeCloseTo(3888);
    expect(timeDomain([60, 3600], "log")).toEqual([50, 4320]);
  });
});
