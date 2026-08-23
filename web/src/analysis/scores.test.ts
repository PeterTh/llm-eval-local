import { describe, expect, it } from "vitest";

import type { RunRecord } from "../data/types";
import { manifestFixture, runsFixture } from "../test/fixtures";
import { deterministicJitter, summarizeModelScores } from "./scores";

function scoredRun(score: number, repetition: number): RunRecord {
  return {
    ...runsFixture[0]!,
    id: `quartile-run-${repetition}`,
    repetition,
    overallScore: score,
    scoreBandId: score <= 4 ? "invalid" : score === 5 ? "no-speedup" : score <= 7 ? "ok" : "good-top",
  };
}

describe("summarizeModelScores", () => {
  it("computes interpolated quartiles, Tukey whiskers, outliers, and the filtered mean", () => {
    const runs = [0, 1, 2, 3, 4, 10].map((score, index) => scoredRun(score, index + 1));
    const [summary] = summarizeModelScores(runs, manifestFixture, {
      models: [], benchmarks: [], backends: [], sort: "weakest",
    });

    expect(summary).toMatchObject({
      runCount: 6,
      meanScore: 20 / 6,
      lowerWhisker: 0,
      firstQuartile: 1.25,
      median: 2.5,
      thirdQuartile: 3.75,
      upperWhisker: 4,
      outlierCount: 1,
    });
    expect(summary?.points.at(-1)).toMatchObject({ score: 10, isOutlier: true });
  });

  it("supports unbalanced subsets, missing cells, unknown IDs, and deterministic sorting", () => {
    const all = summarizeModelScores(runsFixture, manifestFixture, {
      models: [], benchmarks: [], backends: [], sort: "weakest",
    });
    expect(all.map((summary) => summary.modelId)).toEqual(["model/a?x", "unknown-model"]);
    expect(all[0]).toMatchObject({ runCount: 2, meanScore: 6, modelHarnessLabel: "GitHub Copilot CLI" });
    expect(all[1]).toMatchObject({ runCount: 1, meanScore: 10, modelLabel: "unknown-model", modelHarnessLabel: "Not recorded" });

    const filtered = summarizeModelScores(runsFixture, manifestFixture, {
      models: ["model/a?x"], benchmarks: ["bench&one"], backends: ["gpu+x"], sort: "strongest",
    });
    expect(filtered).toHaveLength(1);
    expect(filtered[0]?.points.map((point) => point.runId)).toEqual([
      "bench&one_model/a?x_gpu+x_r1",
      "bench&one_model/a?x_gpu+x_r2",
    ]);

    expect(summarizeModelScores(runsFixture, manifestFixture, {
      models: [], benchmarks: ["missing-cell"], backends: [], sort: "weakest",
    })).toEqual([]);
  });

  it("derives stable bounded jitter from arbitrary run identifiers", () => {
    const first = deterministicJitter("run/with spaces?and=symbols");
    expect(first).toBe(deterministicJitter("run/with spaces?and=symbols"));
    expect(first).toBeGreaterThanOrEqual(0.1);
    expect(first).toBeLessThanOrEqual(0.9);
    expect(first).not.toBe(deterministicJitter("different-run"));
  });
});
