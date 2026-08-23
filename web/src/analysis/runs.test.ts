import { describe, expect, it } from "vitest";

import { runsFixture } from "../test/fixtures";
import { filterRuns, sortRuns } from "./runs";

describe("run filtering", () => {
  it("combines arbitrary entity IDs, exact scores, outcomes, and text search", () => {
    const result = filterRuns(runsFixture, {
      models: ["model/a?x"], scoreBands: ["good-top"], exactScore: 8,
      validation: "passed", benchmark: "successful", query: "BENCH&ONE",
    });
    expect(result.map((run) => run.repetition)).toEqual([2]);
  });

  it("distinguishes failed benchmarks from unavailable benchmarks", () => {
    const base = { models: [], scoreBands: [], exactScore: null, validation: "all" as const, query: "" };
    expect(filterRuns(runsFixture, { ...base, benchmark: "failed" }).map((run) => run.id)).toEqual([runsFixture[2]?.id]);
    expect(filterRuns(runsFixture, { ...base, benchmark: "unavailable" }).map((run) => run.id)).toEqual([runsFixture[0]?.id]);
  });

  it("sorts without requiring a known display label", () => {
    const sorted = sortRuns(runsFixture, "score-desc", new Map([["model/a?x", "Model A"]]));
    expect(sorted.map((run) => run.overallScore)).toEqual([10, 8, 4]);
  });
});
