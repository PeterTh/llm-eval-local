import { describe, expect, it } from "vitest";

import type { DatasetManifest, ScoreCubeCell } from "../data/types";
import { manifestFixture } from "../test/fixtures";
import { analyzeComplexity } from "./complexity";

const cube: ScoreCubeCell[] = [
  { modelId: "model/a?x", benchmarkId: "bench&one", backendId: "gpu+x", score: 0, count: 1 },
  { modelId: "model/a?x", benchmarkId: "bench&one", backendId: "gpu+x", score: 4, count: 1 },
  { modelId: "model/a?x", benchmarkId: "bench&one", backendId: "cpu", score: 8, count: 1 },
  { modelId: "model/outside", benchmarkId: "bench/two?", backendId: "target+new", score: 10, count: 2 },
];

describe("analyzeComplexity", () => {
  it("computes weighted category statistics, grand mean, and easiest-first ordering", () => {
    const result = analyzeComplexity(cube, manifestFixture, { models: [], benchmarks: [], backends: [] });

    expect(result).toMatchObject({ runCount: 5, modelCount: 2, grandMean: 6.4 });
    expect(result.benchmarkSummaries.map((summary) => summary.categoryId)).toEqual(["bench/two?", "bench&one"]);
    expect(result.benchmarkSummaries[0]).toMatchObject({
      categoryLabel: "bench/two?", runCount: 2, meanScore: 10,
      firstQuartile: 10, median: 10, thirdQuartile: 10,
    });
    expect(result.benchmarkSummaries[1]).toMatchObject({
      categoryLabel: "Bench & One", runCount: 3, meanScore: 4,
      firstQuartile: 2, median: 4, thirdQuartile: 6,
    });
    expect(result.backendSummaries.map((summary) => summary.categoryId)).toEqual(["target+new", "cpu", "gpu+x"]);
    expect(result.benchmarkObservations).toHaveLength(5);
    expect(result.backendObservations).toHaveLength(5);
    expect(result.backendObservations.every((observation) => observation.grandMean === 6.4)).toBe(true);
  });

  it("recomputes all statistics for unbalanced arbitrary-ID subsets and missing cells", () => {
    const selectedModel = analyzeComplexity(cube, manifestFixture, {
      models: ["model/a?x"], benchmarks: [], backends: [],
    });
    expect(selectedModel).toMatchObject({ runCount: 3, modelCount: 1, grandMean: 4 });
    expect(selectedModel.benchmarkSummaries.map((summary) => summary.categoryId)).toEqual(["bench&one"]);
    expect(selectedModel.backendSummaries.map((summary) => summary.categoryId)).toEqual(["cpu", "gpu+x"]);

    const selectedBackend = analyzeComplexity(cube, manifestFixture, {
      models: [], benchmarks: [], backends: ["gpu+x"],
    });
    expect(selectedBackend).toMatchObject({ runCount: 2, grandMean: 2 });
    expect(selectedBackend.benchmarkSummaries[0]).toMatchObject({ runCount: 2, meanScore: 2 });

    expect(analyzeComplexity(cube, manifestFixture, {
      models: [], benchmarks: ["missing-cell"], backends: [],
    })).toEqual({
      benchmarkSummaries: [], benchmarkObservations: [],
      backendSummaries: [], backendObservations: [],
      runCount: 0, modelCount: 0, grandMean: null,
    });
  });

  it("keeps categories distinct when optional labels collide", () => {
    const manifest: DatasetManifest = {
      ...manifestFixture,
      benchmarks: [...manifestFixture.benchmarks, { id: "duplicate", label: "Bench & One" }],
    };
    const result = analyzeComplexity([
      ...cube,
      { modelId: "model/a?x", benchmarkId: "duplicate", backendId: "cpu", score: 6, count: 1 },
    ], manifest, { models: [], benchmarks: [], backends: [] });
    const colliding = result.benchmarkSummaries.filter((summary) => summary.categoryLabel === "Bench & One");
    expect(colliding.map((summary) => summary.categoryKey).sort()).toEqual([
      "Bench & One (bench&one)", "Bench & One (duplicate)",
    ]);
  });
});
