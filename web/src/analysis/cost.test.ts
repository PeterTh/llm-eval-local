import { describe, expect, it } from "vitest";

import { costDatasetFixture, manifestFixture } from "../test/fixtures";
import { adaptiveScoreDomain, analyzeCost, costDomain, pricedTokenCountForRun } from "./cost";

describe("score and cost analysis", () => {
  it("recomputes separate score and cost aggregates for unbalanced active subsets", () => {
    const dataset = {
      ...costDatasetFixture,
      runs: costDatasetFixture.runs.map((run) => run.id.endsWith("r2")
        ? { ...run, estimatedCostUsd: null }
        : run),
    };
    const analysis = analyzeCost(dataset, manifestFixture, {
      models: ["model/a?x"], benchmarks: ["bench&one"], backends: ["gpu+x"],
    });

    expect(analysis.models).toHaveLength(1);
    expect(analysis.models[0]).toMatchObject({
      modelId: "model/a?x",
      scoreRunCount: 2,
      costRunCount: 1,
      unavailableCostRunCount: 1,
      meanScore: 6,
      meanEstimatedCostUsd: 0.000108,
      meanPricedTokens: 120,
      pricingProfileId: "unknown-model",
      pricingProvider: "Test provider",
      runCountsLabel: "2 scored · 1 costed",
      providerSummaryLabel: "Test provider · test/fp8",
    });
    expect(analysis.models[0]!.tokenSummaryLabel).toContain("100 input · 80 cached · 20 output · 120 priced");
    expect(analysis.models[0]!.rateSummaryLabel).toContain("input");
    expect(analysis).toMatchObject({ scoreRunCount: 2, costRunCount: 1, unavailableCostRunCount: 1 });
  });

  it("keeps unknown and unpriced entities explicit without inventing zero cost", () => {
    const dataset = {
      ...costDatasetFixture,
      runs: costDatasetFixture.runs.map((run) => run.modelId === "unknown-model"
        ? { ...run, pricingProfileId: null, estimatedCostUsd: null }
        : run),
    };
    const analysis = analyzeCost(dataset, manifestFixture, {
      models: ["unknown-model"], benchmarks: [], backends: [],
    });
    expect(analysis.models[0]).toMatchObject({
      modelLabel: "unknown-model",
      scoreRunCount: 1,
      costRunCount: 0,
      meanEstimatedCostUsd: null,
      costMethod: "Cost unavailable",
    });
    expect(analysis.plottedModels).toEqual([]);
    expect(analysis.unpricedModelCount).toBe(1);
  });

  it("supports missing cells and derives deterministic model identities", () => {
    expect(analyzeCost(costDatasetFixture, manifestFixture, {
      models: [], benchmarks: ["missing-cell"], backends: [],
    }).models).toEqual([]);

    const first = analyzeCost(costDatasetFixture, manifestFixture, {
      models: ["model/a?x"], benchmarks: [], backends: [],
    }).models[0]!;
    const second = analyzeCost(costDatasetFixture, manifestFixture, {
      models: ["model/a?x"], benchmarks: [], backends: [],
    }).models[0]!;
    expect({ shape: first.pointShape, style: first.styleIndex }).toEqual({ shape: second.pointShape, style: second.styleIndex });
  });

  it("reports convention-aware priced token volume for individual runs", () => {
    const run = costDatasetFixture.runs[0]!;
    expect(pricedTokenCountForRun(run, "includes-cached")).toBe(120);
    expect(pricedTokenCountForRun(run, "excludes-cached")).toBe(200);
    expect(pricedTokenCountForRun({
      ...run,
      inputTokens: null,
      cachedInputTokens: null,
      outputTokens: null,
    }, "includes-cached")).toBe(120);
  });

  it("computes deterministic adaptive score and cost domains", () => {
    expect(adaptiveScoreDomain([4, 8], 0, 10)).toEqual([3.68, 8.32]);
    expect(adaptiveScoreDomain([6], 0, 10)).toEqual([5.5, 6.5]);
    expect(adaptiveScoreDomain([0], 0, 10)).toEqual([0, 0.5]);
    expect(adaptiveScoreDomain([], 0, 10)).toEqual([0, 10]);
    expect(costDomain([0.1, 1], "log")).toEqual([0.1 / 1.2, 1.2]);
    expect(costDomain([0.1, 1], "linear")).toEqual([0, 1.08]);
    const singleCostDomain = costDomain([0.2], "log");
    expect(singleCostDomain[0]).toBeCloseTo(0.2 / 1.5, 12);
    expect(singleCostDomain[1]).toBeCloseTo(0.3, 12);
  });
});
