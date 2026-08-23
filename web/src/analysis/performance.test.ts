import { describe, expect, it } from "vitest";

import type { RunRecord } from "../data/types";
import { manifestFixture, runsFixture } from "../test/fixtures";
import { analyzePerformance, resolvePerformanceCell } from "./performance";

function timedRun(
  id: string,
  modelId: string,
  repetition: number,
  medianMs: number,
  measurements: number[],
): RunRecord {
  return {
    ...runsFixture[1]!,
    id,
    modelId,
    repetition,
    benchmarkMedianMs: medianMs,
    benchmarkMeasurementsMs: measurements,
  };
}

describe("performance analysis", () => {
  it("resolves the configured cell and respects requested observed dimensions", () => {
    expect(resolvePerformanceCell(manifestFixture, [], [])).toMatchObject({
      benchmarkId: "bench&one",
      backendId: "gpu+x",
    });
    expect(resolvePerformanceCell(manifestFixture, ["bench&one"], [])).toMatchObject({
      benchmarkId: "bench&one",
      backendId: "gpu+x",
    });
    expect(resolvePerformanceCell(manifestFixture, ["missing-cell"], [])).toBeNull();
  });

  it("keeps the full-cell fastest run as the relative denominator under model filters", () => {
    const cellRuns = [
      timedRun("model-a-r1", "model/a?x", 1, 20, [18, 20, 22]),
      timedRun("model-a-r2", "model/a?x", 2, 30, [27, 30, 33]),
      timedRun("other-r1", "unknown-model", 1, 10, [9, 10, 11]),
    ];
    const analysis = analyzePerformance(
      cellRuns,
      manifestFixture,
      { models: ["model/a?x"], performanceMode: "relative" },
      "fastest",
    );

    expect(analysis.fullCellFastestMs).toBe(10);
    expect(analysis.models).toHaveLength(1);
    expect(analysis.models[0]).toMatchObject({
      modelId: "model/a?x",
      attemptedRunCount: 2,
      successfulRunCount: 2,
      medianMs: 25,
      relativeMedian: 2.5,
      plotMedian: 2.5,
    });
    expect(analysis.models[0]!.points[0]).toMatchObject({
      medianMs: 20,
      relativeToFastest: 2,
      plotValue: 2,
      plotMinimum: 1.8,
      plotMaximum: 2.2,
    });
  });

  it("orders timed models by performance and retains unsuccessful or missing models last", () => {
    const failed = {
      ...runsFixture[2]!,
      id: "other-failed",
      benchmarkSuccess: false,
    } satisfies RunRecord;
    const analysis = analyzePerformance(
      [
        timedRun("model-a-r1", "model/a?x", 1, 20, [19, 20, 21]),
        failed,
      ],
      manifestFixture,
      { models: [], performanceMode: "absolute" },
      "fastest",
    );

    expect(analysis.models.map((model) => model.modelId)).toEqual(["model/a?x", "unknown-model"]);
    expect(analysis.models[0]!.plotMedian).toBe(20);
    expect(analysis.models[1]).toMatchObject({
      attemptedRunCount: 1,
      successfulRunCount: 0,
      benchmarkFailureCount: 1,
      omittedRunCount: 1,
      medianMs: null,
      zeroSuccessLabel: "0/1 successful",
    });
    expect(analysis).toMatchObject({
      attemptedRunCount: 2,
      successfulRunCount: 1,
      benchmarkFailureCount: 1,
      notBenchmarkedCount: 0,
      omittedRunCount: 1,
    });
  });

  it("sorts timed models in reverse performance order", () => {
    const analysis = analyzePerformance(
      [
        timedRun("model-a-r1", "model/a?x", 1, 20, [20]),
        timedRun("other-r1", "unknown-model", 1, 10, [10]),
      ],
      manifestFixture,
      { models: [], performanceMode: "absolute" },
      "slowest",
    );
    expect(analysis.models.map((model) => model.modelId)).toEqual(["model/a?x", "unknown-model"]);
  });
});
