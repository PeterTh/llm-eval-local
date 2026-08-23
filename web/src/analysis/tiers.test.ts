import { describe, expect, it } from "vitest";

import { manifestFixture, scoreCubeFixture } from "../test/fixtures";
import { aggregateTiers } from "./tiers";

describe("aggregateTiers", () => {
  it("uses exact tier boundaries and model-specific sample sizes", () => {
    const cube = [
      ...scoreCubeFixture,
      ...[0, 5, 6, 7, 10].map((score) => ({ modelId: "model/a?x", benchmarkId: "bench&one", backendId: "gpu+x", score, count: 1 })),
    ];
    const [modelA] = aggregateTiers(cube, manifestFixture, { models: ["model/a?x"], benchmarks: [], backends: [], sort: "weakest" });
    expect(modelA?.segments.map((segment) => segment.count)).toEqual([2, 1, 2, 2]);
    expect(modelA?.runCount).toBe(7);
    expect(modelA?.meanScore).toBeCloseTo(40 / 7);
    expect(modelA).toMatchObject({
      modelHarnessLabel: "GitHub Copilot CLI",
      modelInvocationLabel: "provider/model-a",
    });
  });

  it("supports unbalanced observations, missing cells, raw IDs, and subset recomputation", () => {
    const all = aggregateTiers(scoreCubeFixture, manifestFixture, { models: [], benchmarks: [], backends: [], sort: "weakest" });
    expect(all.map((model) => model.modelId)).toEqual(["model/a?x", "unknown-model"]);
    expect(all[1]?.modelLabel).toBe("unknown-model");
    expect(all[1]).toMatchObject({ modelHarnessLabel: "Not recorded", modelInvocationLabel: "Not recorded" });
    expect(all[0]?.runCount).toBe(2);
    expect(all[1]?.runCount).toBe(1);

    const missing = aggregateTiers(scoreCubeFixture, manifestFixture, { models: [], benchmarks: ["missing-cell"], backends: [], sort: "weakest" });
    expect(missing).toEqual([]);
  });

  it("sorts by filtered mean in both directions and alphabetically", () => {
    const weakest = aggregateTiers(scoreCubeFixture, manifestFixture, { models: [], benchmarks: [], backends: [], sort: "weakest" });
    const strongest = aggregateTiers(scoreCubeFixture, manifestFixture, { models: [], benchmarks: [], backends: [], sort: "strongest" });
    const alphabetical = aggregateTiers(scoreCubeFixture, manifestFixture, { models: [], benchmarks: [], backends: [], sort: "alphabetical" });
    expect(weakest.map((model) => model.modelId)).toEqual(["model/a?x", "unknown-model"]);
    expect(strongest.map((model) => model.modelId)).toEqual(["unknown-model", "model/a?x"]);
    expect(alphabetical.map((model) => model.modelId)).toEqual(["model/a?x", "unknown-model"]);
  });
});
