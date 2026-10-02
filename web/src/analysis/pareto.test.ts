import { describe, expect, it } from "vitest";

import { costDatasetFixture, manifestFixture, timeDatasetFixture } from "../test/fixtures";
import { analyzeCost } from "./cost";
import { getParetoModelIds } from "./pareto";
import { analyzeTime } from "./time";

describe("Pareto front", () => {
  it.each([
    { name: "empty selection", values: [], expected: [] },
    { name: "singleton", values: [[2, 7]], expected: [0] },
    { name: "tradeoffs and a dominated point", values: [[1, 5], [2, 8], [3, 7], [4, 9]], expected: [0, 1, 3] },
    { name: "equal resource use", values: [[1, 5], [1, 8]], expected: [1] },
    { name: "equal scores", values: [[2, 8], [1, 8]], expected: [1] },
    { name: "identical frontier coordinates", values: [[1, 8], [1, 8], [2, 9]], expected: [0, 1, 2] },
    { name: "identical dominated coordinates", values: [[2, 8], [2, 8], [1, 9]], expected: [2] },
    { name: "score differences hidden by rounding", values: [[1, 8.00001], [1, 8.00002]], expected: [1] },
    { name: "cost differences hidden by rounding", values: [[0.010002, 8], [0.010001, 8]], expected: [1] },
    { name: "zero scores", values: [[1, 0], [2, 0]], expected: [0] },
  ])("handles $name", ({ values, expected }) => {
    const points = values.map(([value, score], index) => ({ modelId: String(index), value: value!, score: score! }));
    expect(getParetoModelIds(points)).toEqual(expected.map(String));
    expect(getParetoModelIds([...points].reverse()).sort()).toEqual(expected.map(String).sort());
  });
});

const all = { models: [], benchmarks: [], backends: [] };
const modelA = "model/a?x";
const modelB = "unknown-model";

describe.each(["cost", "time"] as const)("%s Pareto analysis", (kind) => {
  const observations = [
    { modelId: modelA, benchmarkId: "first", backendId: "first", overallScore: 5, value: 60 },
    { modelId: modelB, benchmarkId: "first", backendId: "first", overallScore: 7, value: 30 },
    { modelId: modelA, benchmarkId: "second", backendId: "second", overallScore: 9, value: 60 },
    { modelId: modelB, benchmarkId: "second", backendId: "second", overallScore: 2, value: 180 },
  ];
  const analyze = (filters: { models: string[]; benchmarks: string[]; backends: string[] }, missing = false) => {
    if (kind === "cost") {
      return analyzeCost({ ...costDatasetFixture, runs: observations.map(({ value, ...run }, index) => ({
        ...costDatasetFixture.runs[0]!, ...run, id: String(index), estimatedCostUsd: missing ? null : value,
      })) }, manifestFixture, filters);
    }
    return analyzeTime({ ...timeDatasetFixture, runs: observations.map(({ value, ...run }, index) => ({
      ...timeDatasetFixture.runs[0]!, ...run, id: String(index), generationTimeSeconds: missing ? null : value,
    })) }, manifestFixture, filters);
  };

  it.each(["benchmarks", "backends"] as const)("recomputes aggregates and membership when %s change", (dimension) => {
    expect(analyze(all).paretoModelIds).toEqual([modelA]);
    expect(analyze({ ...all, [dimension]: ["first"] }).paretoModelIds).toEqual([modelB]);
    expect(analyze({ ...all, [dimension]: ["second"] }).paretoModelIds).toEqual([modelA]);
  });

  it("promotes a model when its dominator is hidden", () => {
    const selected = { ...all, benchmarks: ["first"] };
    expect(analyze(selected).paretoModelIds).toEqual([modelB]);
    expect(analyze({ ...selected, models: [modelA] }).paretoModelIds).toEqual([modelA]);
  });

  it("does not evaluate unavailable or empty selections", () => {
    expect(analyze(all, true)).toMatchObject({ plottedModels: [], paretoModelIds: [] });
    expect(analyze({ ...all, benchmarks: ["missing"] }).paretoModelIds).toEqual([]);
  });
});
